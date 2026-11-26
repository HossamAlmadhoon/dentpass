// Version 2 checks: editing, photos, location, search, profiles, ratings, admin, delete account.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const URL = process.env.API_URL;
const ANON = process.env.ANON_KEY || process.env.PUBLISHABLE_KEY;
const SERVICE = process.env.SERVICE_ROLE_KEY || process.env.SECRET_KEY;
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(URL, SERVICE, opts);
const IMAGE = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);
const run = `${Date.now()}v2`;

function ok({ error, data }, step) {
  if (error) throw new Error(`${step}: ${error.message}`);
  return data;
}
async function fails(promise, text, step) {
  const { error } = await promise;
  assert.ok(error, `${step}: expected an error containing "${text}"`);
  assert.match(error.message, new RegExp(text, 'i'), step);
}
const inDays = (d, hours = 0) => new Date(Date.now() + d * 864e5 + hours * 36e5).toISOString();

async function approvedMember(name, phone) {
  const c = createClient(URL, ANON, opts);
  const email = `${name}-${run}@example.com`;
  const { data, error } = await c.auth.signUp({ email, password: 'password123' });
  if (error) throw error;
  const id = data.user.id;
  ok(await service.from('profiles').update({
    full_name: `Dr ${name}`, phone, role: 'dentist', syndicate_no: '1', area: 'nasr_city', status: 'approved',
    card_path: `${id}/c.jpg`, id_path: `${id}/i.jpg`,
  }).eq('id', id), `approve ${name}`);
  return { c, id, email, name };
}

test('DentPass version 2', async () => {
  const host = await approvedMember('host', '01000000001');
  const guest = await approvedMember('guest', '01000000002');
  const other = await approvedMember('other', '01000000003');
  const admin = await approvedMember('admin', '01000000004');
  ok(await service.from('profiles').update({ is_admin: true }).eq('id', admin.id), 'make admin');

  // ---- Profile editing after approval: photo, bio, area and phone yes; name no
  const avatar = `${host.id}/avatar-${run}.jpg`;
  ok(await host.c.storage.from('avatars').upload(avatar, IMAGE, { upsert: true, contentType: 'image/png' }), 'upload profile photo');
  ok(await host.c.storage.from('avatars').upload(avatar, IMAGE, { upsert: true, contentType: 'image/png' }), 'replace profile photo');
  ok(await host.c.from('profiles').update({ bio: 'Implantologist, 12 years', area: 'heliopolis', phone: '01000000011', avatar_path: avatar }).eq('id', host.id), 'edit profile');
  await fails(host.c.from('profiles').update({ full_name: 'New name' }).eq('id', host.id), 'locked', 'name stays locked');
  await fails(guest.c.storage.from('avatars').upload(`${host.id}/x.jpg`, IMAGE, { contentType: 'image/png' }), 'row-level security|policy|unauthorized', 'cannot upload into another\'s photos');
  await fails(host.c.storage.from('avatars').upload(`${host.id}/notes.txt`, Buffer.from('hi'), { contentType: 'text/plain' }), 'mime|type|invalid', 'only images are accepted');

  // ---- Slot with several photos and a location
  const photos = [`${host.id}/a-${run}.jpg`, `${host.id}/b-${run}.jpg`];
  for (const p of photos) ok(await host.c.storage.from('slot-photos').upload(p, IMAGE, { contentType: 'image/png' }), 'upload slot photo');
  const base = {
    host_id: host.id, description: 'Live sinus lift', area: 'heliopolis', address: '5 Baghdad St',
    capacity: 2, price_egp: 1200, need_role: null, lat: 30.091234, lng: 31.322345,
  };
  ok(await host.c.from('slots').insert({ ...base, kind: 'observe', title: `Sinus lift ${run}`, photo_paths: photos, starts_at: inDays(3), ends_at: inDays(3, 3) }), 'post with photos and location');
  ok(await host.c.from('slots').insert({ ...base, kind: 'course', title: `Composite course ${run}`, description: 'Hands-on veneers', photo_paths: [], starts_at: inDays(20), ends_at: inDays(20, 6) }), 'post a later course');

  // ---- Search, dates and host filter
  const byWord = ok(await guest.c.rpc('get_feed', { p_kind: null, p_area: null, p_query: 'sinus', p_from: null, p_to: null, p_host: null }), 'search by word');
  assert.ok(byWord.some((s) => s.title === `Sinus lift ${run}`) && !byWord.some((s) => s.title === `Composite course ${run}`));
  const byHostName = ok(await guest.c.rpc('get_feed', { p_query: 'Dr host' }), 'search by host name');
  assert.ok(byHostName.length >= 2);
  const thisWeek = ok(await guest.c.rpc('get_feed', { p_from: inDays(0), p_to: inDays(7), p_host: host.id }), 'this week');
  assert.deepEqual(thisWeek.map((s) => s.title), [`Sinus lift ${run}`]);
  const card = thisWeek[0];
  assert.equal(card.photo_paths.length, 2);
  assert.equal(card.lat, 30.09, 'public pin is rounded');
  assert.equal(card.lng, 31.32);
  assert.equal(card.host_reviews, 0);
  const v1Call = ok(await guest.c.rpc('get_feed', { p_kind: ['observe'], p_area: 'heliopolis' }), 'version 1 app call still works');
  assert.ok(v1Call.length >= 1);

  const slotId = card.id;
  let seen = ok(await guest.c.rpc('get_slot', { p_slot: slotId }), 'details as guest')[0];
  assert.equal(seen.lat, 30.09);
  assert.equal(seen.exact_location, false);
  const mine = ok(await host.c.rpc('get_slot', { p_slot: slotId }), 'details as host')[0];
  assert.equal(mine.lat, 30.091234);
  assert.equal(mine.host_phone, null, 'host does not need their own phone');

  // ---- Booking, then the host edits
  const gb = ok(await guest.c.rpc('book_slot', { p_slot: slotId, p_message: '' }), 'guest books');
  ok(await other.c.rpc('book_slot', { p_slot: slotId, p_message: '' }), 'other books');
  const reqs = ok(await host.c.rpc('get_slot_requests', { p_slot: slotId }), 'requests');
  for (const r of reqs) ok(await host.c.rpc('respond_booking', { p_booking: r.id, p_accept: true }), 'accept');
  seen = ok(await guest.c.rpc('get_slot', { p_slot: slotId }), 'details after acceptance')[0];
  assert.equal(seen.lat, 30.091234, 'exact location after acceptance');
  assert.equal(seen.host_phone, '01000000011');

  await fails(host.c.from('slots').update({ capacity: 1 }).eq('id', slotId), 'capacity below accepted', 'cannot drop below accepted people');
  await fails(host.c.from('slots').update({ kind: 'rent' }).eq('id', slotId), 'cannot change type', 'type is fixed');
  await fails(guest.c.from('slots').update({ title: 'Hacked' }).eq('id', slotId).select().single(), '.', 'others cannot edit');
  ok(await host.c.from('slots').update({ starts_at: inDays(4), ends_at: inDays(4, 3), title: `Sinus lift ${run}`, photo_paths: [photos[1]] }).eq('id', slotId), 'host edits time and photos');
  ok(await host.c.storage.from('slot-photos').remove([photos[0]]), 'host removes an old photo');
  const updates = ok(await guest.c.from('notifications').select('type, slot_title').eq('user_id', guest.id).eq('type', 'slot_updated'), 'guest told about the change');
  assert.equal(updates.length, 1);
  assert.equal(updates[0].slot_title, `Sinus lift ${run}`);

  // ---- Ratings: only after the slot has ended, only by the two people involved
  await fails(guest.c.rpc('submit_review', { p_booking: gb.id, p_stars: 5, p_comment: '' }), 'not finished', 'no rating before the end');
  ok(await service.from('slots').update({ starts_at: inDays(-1, -3), ends_at: inDays(-1) }).eq('id', slotId), 'move the slot into the past');
  await fails(other.c.rpc('submit_review', { p_booking: gb.id, p_stars: 1, p_comment: '' }), 'not your booking', 'a third person cannot rate');
  await fails(guest.c.rpc('submit_review', { p_booking: gb.id, p_stars: 7, p_comment: '' }), 'stars', 'stars must be 1 to 5');
  ok(await guest.c.rpc('submit_review', { p_booking: gb.id, p_stars: 4, p_comment: 'Very clear teaching' }), 'guest rates host');
  ok(await guest.c.rpc('submit_review', { p_booking: gb.id, p_stars: 5, p_comment: 'Excellent teaching' }), 'guest changes their rating');
  ok(await host.c.rpc('submit_review', { p_booking: gb.id, p_stars: 5, p_comment: 'On time, careful' }), 'host rates guest');
  await fails(guest.c.from('reviews').insert({ reviewer_id: guest.id, reviewee_id: host.id, stars: 5 }), 'row-level security|policy', 'ratings only through the function');

  const hostPage = ok(await other.c.rpc('get_member', { p_user: host.id }), 'host page')[0];
  assert.equal(Number(hostPage.rating), 5);
  assert.equal(hostPage.reviews, 1);
  assert.equal(hostPage.bio, 'Implantologist, 12 years');
  assert.equal(hostPage.hosted, 2);
  const guestPage = ok(await other.c.rpc('get_member', { p_user: guest.id }), 'guest page')[0];
  assert.equal(guestPage.attended, 1);
  const hostReviews = ok(await other.c.rpc('get_reviews', { p_user: host.id }), 'host reviews');
  assert.equal(hostReviews[0].comment, 'Excellent teaching');
  assert.equal(hostReviews[0].reviewer_name, 'Dr guest');
  const after = ok(await host.c.rpc('get_slot_requests', { p_slot: slotId }), 'requests show who was rated');
  assert.equal(after.find((r) => r.user_id === guest.id).reviewed, true);
  assert.equal(after.find((r) => r.user_id === other.id).reviewed, false);
  const told = ok(await host.c.from('notifications').select('type').eq('user_id', host.id).eq('type', 'review_received'), 'host told about the rating');
  assert.ok(told.length >= 1);

  // ---- Admin: suspend, reinstate, overview, remove a slot
  await fails(guest.c.rpc('set_member_status', { p_user: other.id, p_suspend: true, p_reason: '' }), 'admins only', 'only admins suspend');
  ok(await admin.c.rpc('set_member_status', { p_user: other.id, p_suspend: true, p_reason: 'No-shows' }), 'admin suspends');
  await fails(other.c.rpc('get_feed', {}), 'not approved', 'suspended member is locked out');
  ok(await admin.c.rpc('set_member_status', { p_user: other.id, p_suspend: false, p_reason: null }), 'admin reinstates');
  ok(await other.c.rpc('get_feed', {}), 'reinstated member is back');
  const overview = ok(await admin.c.rpc('admin_overview'), 'overview');
  assert.ok(overview.members >= 4 && overview.accepted_30d >= 2, JSON.stringify(overview));
  await fails(guest.c.rpc('admin_overview'), 'admins only', 'overview is for admins');

  const later = ok(await guest.c.rpc('get_feed', { p_query: 'Composite course' }), 'find the course')[0];
  ok(await guest.c.rpc('book_slot', { p_slot: later.id, p_message: '' }), 'guest books the course');
  ok(await admin.c.from('slots').delete().eq('id', later.id), 'admin removes the course');
  const cancelled = ok(await guest.c.from('notifications').select('type, slot_title').eq('user_id', guest.id).eq('type', 'slot_cancelled'), 'guest told it was cancelled');
  assert.equal(cancelled[0].slot_title, `Composite course ${run}`);

  // ---- Delete my account
  ok(await other.c.storage.from('slot-photos').list(other.id), 'list own files');
  ok(await other.c.rpc('delete_my_account'), 'delete account');
  const gone = ok(await service.from('profiles').select('id').eq('id', other.id), 'profile removed');
  assert.equal(gone.length, 0);
  const again = createClient(URL, ANON, opts);
  const { error } = await again.auth.signInWithPassword({ email: other.email, password: 'password123' });
  assert.ok(error, 'deleted account cannot sign in');
  // The host's ratings survive the guest leaving? Ratings by a deleted member go with them.
  const stillThere = ok(await guest.c.rpc('get_member', { p_user: host.id }), 'host page after a member left')[0];
  assert.equal(stillThere.reviews, 1);
});
