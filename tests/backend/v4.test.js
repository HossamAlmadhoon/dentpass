// Optional verification: members browse and book with basic details; posting needs verified papers.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const URL = process.env.API_URL;
const ANON = process.env.ANON_KEY || process.env.PUBLISHABLE_KEY;
const SERVICE = process.env.SERVICE_ROLE_KEY || process.env.SECRET_KEY;
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(URL, SERVICE, opts);
const run = `${Date.now()}v4`;
const IMAGE = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64');

function ok({ error, data }, step) {
  if (error) throw new Error(`${step}: ${error.message}`);
  return data;
}
async function fails(promise, text, step) {
  const { error } = await promise;
  assert.ok(error, `${step}: expected an error containing "${text}"`);
  assert.match(error.message, new RegExp(text, 'i'), step);
}
const inHours = (h) => new Date(Date.now() + h * 36e5).toISOString();

async function signUp(name) {
  const c = createClient(URL, ANON, opts);
  const { data, error } = await c.auth.signUp({ email: `${name}-${run}@example.com`, password: 'password123' });
  if (error) throw error;
  return { c, id: data.user.id, name };
}
async function verified(name, extra = {}) {
  const m = await signUp(name);
  ok(await service.from('profiles').update({
    full_name: `Dr ${name} ${run}`, phone: '01099990000', role: 'dentist', syndicate_no: '1', area: 'dokki',
    status: 'approved', card_path: `${m.id}/c.jpg`, id_path: `${m.id}/i.jpg`, ...extra,
  }).eq('id', m.id), `approve ${name}`);
  return m;
}
const slot = (host, fields = {}) => ({
  host_id: host.id, title: `Case ${run}`, description: '', kind: 'observe', area: 'dokki', address: '3 Tahrir St',
  capacity: 2, price_egp: 400, need_role: null, photo_paths: [], starts_at: inHours(5), ends_at: inHours(8), ...fields,
});

test('Optional verification', async () => {
  const host = await verified('host');
  const admin = await verified('admin', { is_admin: true });
  const newbie = await signUp('newbie');

  // ---- No basic details yet: locked out
  await fails(newbie.c.rpc('get_feed', {}), 'not approved', 'no name or phone yet');
  ok(await newbie.c.from('profiles').update({ full_name: `Dr Newbie ${run}`, phone: '' }).eq('id', newbie.id), 'name only');
  await fails(newbie.c.rpc('get_feed', {}), 'not approved', 'an empty phone is not enough');

  // ---- Basic details only: in the app, not verified
  ok(await newbie.c.from('profiles').update({
    phone: '01055556666', role: 'dentist', area: 'maadi', accepted_terms_at: new Date().toISOString(),
  }).eq('id', newbie.id), 'basic details');
  const me = ok(await newbie.c.from('profiles').select('status').eq('id', newbie.id).single(), 'read own profile');
  assert.equal(me.status, 'unverified');
  ok(await newbie.c.rpc('get_feed', {}), 'unverified member browses');
  ok(await newbie.c.rpc('my_home'), 'unverified member sees home');
  ok(await newbie.c.from('slot_alerts').insert({ kinds: null, area: 'dokki' }), 'unverified member sets an alert');

  // ---- Posting needs verification
  await fails(newbie.c.from('slots').insert(slot(newbie)), 'row-level security|policy', 'unverified cannot post');

  // Host posts; the alert reaches the unverified member
  const s = ok(await host.c.from('slots').insert(slot(host)).select().single(), 'verified host posts');
  const notes = ok(await newbie.c.from('notifications').select('type, slot_id').eq('user_id', newbie.id), 'newbie notifications');
  assert.ok(notes.some((n) => n.type === 'new_slot' && n.slot_id === s.id), 'alert reaches unverified member');

  // ---- Booking as unverified; host sees the flag
  ok(await newbie.c.rpc('get_slot', { p_slot: s.id }), 'unverified opens a slot');
  const b = ok(await newbie.c.rpc('book_slot', { p_slot: s.id, p_message: 'Hi' }), 'unverified books');
  assert.equal(b.status, 'pending');
  let reqs = ok(await host.c.rpc('get_slot_requests', { p_slot: s.id }), 'host lists requests');
  const req = reqs.find((r) => r.user_id === newbie.id);
  assert.equal(req.verified, false, 'host sees the guest is not verified');
  assert.equal(req.phone, null, 'phone stays hidden until accepted');

  const page = ok(await host.c.rpc('get_member', { p_user: newbie.id }), 'host opens the unverified member');
  assert.equal(page.length, 1);
  assert.equal(page[0].verified, false);
  const hostPage = ok(await newbie.c.rpc('get_member', { p_user: host.id }), 'newbie opens the host');
  assert.equal(hostPage[0].verified, true);

  // ---- Reports and reviews still work for members
  ok(await newbie.c.from('reports').insert({ reporter_id: newbie.id, member_id: host.id, reason: 'other', details: `t ${run}` }), 'unverified can report');

  // ---- Overview counts the unverified
  const o = ok(await admin.c.rpc('admin_overview'), 'overview');
  assert.ok(o.unverified >= 1, 'overview counts members without the verified mark');

  // ---- Suspend and reinstate an unverified member: goes back to unverified
  ok(await admin.c.rpc('set_member_status', { p_user: newbie.id, p_suspend: true, p_reason: 'Check' }), 'suspend unverified');
  await fails(newbie.c.rpc('get_feed', {}), 'not approved', 'suspended is locked out');
  await fails(newbie.c.rpc('book_slot', { p_slot: s.id, p_message: '' }), 'not approved', 'suspended cannot book');
  ok(await admin.c.rpc('set_member_status', { p_user: newbie.id, p_suspend: false, p_reason: null }), 'reinstate');
  const back = ok(await service.from('profiles').select('status').eq('id', newbie.id).single(), 'status after reinstating');
  assert.equal(back.status, 'unverified', 'reinstating restores the earlier status');

  // ---- Later: send papers, get checked, then post
  for (const file of ['syndicate_card.jpg', 'national_id.jpg']) {
    ok(await newbie.c.storage.from('verification').upload(`${newbie.id}/${file}`, IMAGE, { upsert: true, contentType: 'image/png' }), `upload ${file}`);
  }
  ok(await newbie.c.from('profiles').update({
    syndicate_no: '777', card_path: `${newbie.id}/syndicate_card.jpg`, id_path: `${newbie.id}/national_id.jpg`, status: 'pending',
  }).eq('id', newbie.id), 'send papers later');
  ok(await newbie.c.rpc('get_feed', {}), 'still browses while papers are checked');
  await fails(newbie.c.from('slots').insert(slot(newbie)), 'row-level security|policy', 'cannot post while being checked');
  ok(await admin.c.rpc('set_verification', { p_user: newbie.id, p_approve: true, p_reason: null }), 'admin approves');
  ok(await newbie.c.from('slots').insert(slot(newbie, { title: `Newbie chair ${run}`, kind: 'rent', capacity: 1 })), 'verified member posts');
  reqs = ok(await host.c.rpc('get_slot_requests', { p_slot: s.id }), 'host lists requests again');
  assert.equal(reqs.find((r) => r.user_id === newbie.id).verified, true, 'mark shows after approval');
});
