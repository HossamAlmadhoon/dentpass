// End-to-end checks of the database rules, run against a local Supabase on every build.
// Each step makes the same call the app makes (same tables, functions, buckets and options).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const URL = process.env.API_URL;
const ANON = process.env.ANON_KEY || process.env.PUBLISHABLE_KEY;
const SERVICE = process.env.SERVICE_ROLE_KEY || process.env.SECRET_KEY;
assert.ok(URL && ANON && SERVICE, 'API_URL, ANON_KEY and SERVICE_ROLE_KEY must be set');

const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(URL, SERVICE, opts);
// A 1x1 PNG
const IMAGE = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);
const PASSWORD = 'password123';
const run = Date.now();

async function newMember(name) {
  const c = createClient(URL, ANON, opts);
  const email = `${name}-${run}@example.com`;
  const { data, error } = await c.auth.signUp({ email, password: PASSWORD });
  assert.ifError(error);
  assert.ok(data.session, 'sign-up should sign in straight away when email confirmation is off');
  return { c, id: data.user.id, email, name };
}

function ok({ error, data }, step) {
  assert.ifError(error ? new Error(`${step}: ${error.message}`) : null);
  return data;
}

async function fails(promise, text, step) {
  const { error } = await promise;
  assert.ok(error, `${step}: expected an error containing "${text}"`);
  assert.match(error.message, new RegExp(text, 'i'), step);
}

const inDays = (d, hours = 0) => new Date(Date.now() + d * 864e5 + hours * 36e5).toISOString();

test('DentPass: sign-up to booking, with every permission check', async () => {
  const host = await newMember('host');
  const guest = await newMember('guest');
  const stranger = await newMember('stranger');
  const admin = await newMember('admin');

  // The README's "make yourself admin" step, done with the service key
  ok(await service.from('profiles').update({ is_admin: true, status: 'approved', full_name: 'Admin' }).eq('id', admin.id), 'make admin');

  // ---- Verification: upload documents (replace allowed), then submit
  const unapproved = await host.c.rpc('get_feed', { p_kind: null, p_area: null });
  assert.ok(unapproved.error, 'an unapproved member must not see the feed');

  for (const m of [host, guest]) {
    for (const file of ['syndicate_card.jpg', 'national_id.jpg']) {
      ok(await m.c.storage.from('verification').upload(`${m.id}/${file}`, IMAGE, { upsert: true, contentType: 'image/png' }), `${m.name} uploads ${file}`);
    }
    // Re-sending a document after a rejection overwrites it
    ok(await m.c.storage.from('verification').upload(`${m.id}/national_id.jpg`, IMAGE, { upsert: true, contentType: 'image/png' }), `${m.name} re-uploads ID`);

    await fails(
      m.c.from('profiles').update({ status: 'approved' }).eq('id', m.id),
      'not allowed', `${m.name} cannot approve themselves`,
    );
    ok(await m.c.from('profiles').update({
      full_name: `Dr ${m.name}`, phone: m === host ? '01011112222' : '01033334444', role: 'dentist',
      syndicate_no: '12345', area: 'maadi', card_path: `${m.id}/syndicate_card.jpg`,
      id_path: `${m.id}/national_id.jpg`, status: 'pending',
    }).eq('id', m.id), `${m.name} submits for checking`);
  }

  const peek = await guest.c.storage.from('verification').list(host.id);
  assert.equal((peek.data ?? []).length, 0, 'members must not see each other\'s documents');
  await fails(
    stranger.c.storage.from('verification').upload(`${host.id}/national_id.jpg`, IMAGE, { upsert: true, contentType: 'image/png' }),
    'row-level security|unauthorized|policy', 'nobody can upload into someone else\'s folder',
  );

  // ---- Admin review
  const pending = ok(await admin.c.from('profiles').select().eq('status', 'pending').order('submitted_at'), 'admin lists pending');
  assert.ok(pending.some((p) => p.id === host.id), 'admin sees the pending host');
  ok(await admin.c.storage.from('verification').createSignedUrl(`${host.id}/syndicate_card.jpg`, 600), 'admin opens a document');
  await fails(guest.c.rpc('set_verification', { p_user: host.id, p_approve: true, p_reason: null }), 'admins only', 'non-admin cannot approve');
  for (const m of [host, guest]) {
    ok(await admin.c.rpc('set_verification', { p_user: m.id, p_approve: true, p_reason: null }), `approve ${m.name}`);
  }
  // Locked after approval
  await fails(host.c.from('profiles').update({ full_name: 'Someone else' }).eq('id', host.id), 'locked', 'checked details are locked');

  // ---- Posting, with a photo (new file each time, no overwrite)
  const photo = `${host.id}/${run}.jpg`;
  ok(await host.c.storage.from('slot-photos').upload(photo, IMAGE, { upsert: false, contentType: 'image/png' }), 'host uploads a slot photo');
  const publicUrl = host.c.storage.from('slot-photos').getPublicUrl(photo).data.publicUrl;
  assert.match(publicUrl, /slot-photos/);

  const slot = (fields) => ({
    host_id: host.id, description: 'Details', area: 'maadi', address: '12 Road 9, Maadi',
    starts_at: inDays(2), ends_at: inDays(2, 4), capacity: 1, price_egp: 1000, need_role: null, photo_path: null, ...fields,
  });
  ok(await host.c.from('slots').insert(slot({ kind: 'observe', title: 'Implant case', photo_path: photo })), 'post a watch-a-case slot');
  ok(await host.c.from('slots').insert(slot({ kind: 'cover', title: 'Evening shift', need_role: 'dentist', price_egp: 800 })), 'post a cover slot');
  await fails(host.c.from('slots').insert(slot({ kind: 'rent', title: 'Old chair', starts_at: inDays(-1), ends_at: inDays(-1, 2) })), 'row-level security|policy', 'cannot post in the past');
  await fails(stranger.c.from('slots').insert(slot({ host_id: stranger.id, kind: 'rent', title: 'Chair' })), 'row-level security|policy', 'unapproved member cannot post');

  // ---- Explore, with the app's filters
  const learn = ok(await guest.c.rpc('get_feed', { p_kind: ['observe', 'course'], p_area: 'maadi' }), 'feed: Learn in Maadi');
  assert.equal(learn.length, 1);
  assert.equal(learn[0].host_name, 'Dr host');
  const everything = ok(await guest.c.rpc('get_feed', { p_kind: null, p_area: null }), 'feed: all');
  assert.equal(everything.length, 2);
  const caseId = learn[0].id;
  const coverId = everything.find((s) => s.kind === 'cover').id;

  let detail = ok(await guest.c.rpc('get_slot', { p_slot: caseId }), 'slot details')[0];
  assert.equal(detail.address, '', 'address hidden before acceptance');
  assert.equal(detail.host_phone, null, 'phone hidden before acceptance');

  // ---- Booking
  const fee = ok(await guest.c.from('app_settings').select('fee_percent').single(), 'read fee');
  const booking = ok(await guest.c.rpc('book_slot', { p_slot: caseId, p_message: 'Looking forward to it' }), 'book a seat');
  assert.equal(booking.status, 'pending');
  assert.equal(booking.fee_egp, Math.round(1000 * Number(fee.fee_percent) / 100));
  await fails(guest.c.rpc('book_slot', { p_slot: caseId, p_message: '' }), 'already booked', 'no double booking');
  await fails(host.c.rpc('book_slot', { p_slot: caseId, p_message: '' }), 'own slot', 'host cannot book own slot');
  await fails(guest.c.from('bookings').insert({ slot_id: caseId, user_id: guest.id, price_egp: 0, fee_egp: 0 }), 'row-level security|policy', 'bookings only through the booking function');

  const mine = ok(await guest.c.from('bookings').select().eq('slot_id', caseId).eq('user_id', guest.id).maybeSingle(), 'my booking for this slot');
  assert.equal(mine.status, 'pending');
  const myList = ok(await guest.c.from('bookings').select('*, slots(*)').eq('user_id', guest.id).order('created_at', { ascending: false }), 'my bookings');
  assert.equal(myList[0].slots.title, 'Implant case');
  ok(await guest.c.rpc('book_slot', { p_slot: coverId, p_message: '' }), 'offer to cover');

  // ---- Host side
  const posts = ok(await host.c.from('slots').select('*, bookings(status)').eq('host_id', host.id).order('starts_at', { ascending: false }), 'my posts');
  assert.equal(posts.find((p) => p.id === caseId).bookings.length, 1);
  const requests = ok(await host.c.rpc('get_slot_requests', { p_slot: caseId }), 'requests');
  assert.equal(requests.length, 1);
  assert.equal(requests[0].phone, null, 'phone hidden until accepted');
  await fails(guest.c.rpc('get_slot_requests', { p_slot: caseId }), 'not your slot', 'only the host sees requests');
  await fails(guest.c.rpc('respond_booking', { p_booking: requests[0].id, p_accept: true }), 'not your slot', 'only the host answers');
  ok(await host.c.rpc('respond_booking', { p_booking: requests[0].id, p_accept: true }), 'host accepts');

  const afterAccept = ok(await host.c.rpc('get_slot_requests', { p_slot: caseId }), 'requests after accepting')[0];
  assert.equal(afterAccept.phone, '01033334444', 'host sees the guest\'s phone after accepting');
  detail = ok(await guest.c.rpc('get_slot', { p_slot: caseId }), 'slot after acceptance')[0];
  assert.equal(detail.address, '12 Road 9, Maadi');
  assert.equal(detail.host_phone, '01011112222');

  // ---- Notifications
  const notes = ok(await guest.c.from('notifications').select('*, slots(title)').eq('user_id', guest.id).order('created_at', { ascending: false }), 'notifications');
  const types = notes.map((n) => n.type);
  assert.ok(types.includes('verification_approved') && types.includes('booking_accepted'), `guest notifications: ${types}`);
  assert.equal(notes.find((n) => n.type === 'booking_accepted').slots.title, 'Implant case');
  ok(await guest.c.from('notifications').update({ read: true }).eq('user_id', guest.id).eq('read', false), 'mark read');
  const unread = ok(await guest.c.from('notifications').select('id').eq('user_id', guest.id).eq('read', false), 'unread count');
  assert.equal(unread.length, 0);

  // ---- Cancel frees the seat; closing hides the slot
  ok(await guest.c.rpc('cancel_booking', { p_booking: booking.id }), 'guest cancels');
  const hostNotes = ok(await host.c.from('notifications').select('type').eq('user_id', host.id), 'host notifications').map((n) => n.type);
  assert.ok(hostNotes.includes('booking_requested') && hostNotes.includes('booking_cancelled'), `host notifications: ${hostNotes}`);
  ok(await host.c.from('slots').update({ is_open: false }).eq('id', caseId), 'host closes the slot');
  const open = ok(await guest.c.rpc('get_feed', { p_kind: null, p_area: null }), 'feed after closing');
  assert.equal(open.length, 1, 'closed slots leave the feed');

  // ---- Passwords
  ok(await guest.c.auth.resetPasswordForEmail(guest.email, { redirectTo: 'http://127.0.0.1:3000/?reset=1' }), 'send a reset email');
  ok(await guest.c.auth.updateUser({ password: 'newpassword456' }), 'set a new password');
  const again = createClient(URL, ANON, opts);
  ok(await again.auth.signInWithPassword({ email: guest.email, password: 'newpassword456' }), 'sign in with the new password');
});
