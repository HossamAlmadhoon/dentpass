// v5: negotiable prices with offers, InstaPay for accepted guests, "I've paid".
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const URL = process.env.API_URL;
const ANON = process.env.ANON_KEY || process.env.PUBLISHABLE_KEY;
const SERVICE = process.env.SERVICE_ROLE_KEY || process.env.SECRET_KEY;
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(URL, SERVICE, opts);
const run = `${Date.now()}v5`;

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

async function member(name, extra = {}) {
  const c = createClient(URL, ANON, opts);
  const { data, error } = await c.auth.signUp({ email: `${name}-${run}@example.com`, password: 'password123' });
  if (error) throw error;
  const id = data.user.id;
  ok(await service.from('profiles').update({
    full_name: `Dr ${name} ${run}`, phone: '01099990000', role: 'dentist', area: 'dokki', status: 'approved',
    syndicate_no: '1', card_path: `${id}/c.jpg`, id_path: `${id}/i.jpg`, ...extra,
  }).eq('id', id), `set up ${name}`);
  return { c, id };
}
const slot = (host, fields = {}) => ({
  host_id: host.id, title: `Chair ${run}`, description: '', kind: 'rent', area: 'dokki', address: '3 Tahrir St',
  capacity: 3, price_egp: 1000, need_role: null, photo_paths: [], starts_at: inHours(5), ends_at: inHours(9), ...fields,
});

test('Negotiable prices, InstaPay and paid mark', async () => {
  const host = await member('host');
  const guest = await member('guest');
  const other = await member('other', { status: 'unverified', card_path: null, id_path: null, syndicate_no: null });
  ok(await host.c.from('profiles').update({ instapay: 'host@instapay' }).eq('id', host.id), 'host saves InstaPay');

  const fixed = ok(await host.c.from('slots').insert(slot(host)).select().single(), 'fixed price slot');
  const open = ok(await host.c.from('slots').insert(slot(host, { title: `Open ${run}`, negotiable: true })).select().single(), 'negotiable slot');

  // Feed and slot page say which one is negotiable
  const feed = ok(await guest.c.rpc('get_feed', { p_host: host.id }), 'feed');
  assert.equal(feed.find((s) => s.id === open.id).negotiable, true);
  assert.equal(feed.find((s) => s.id === fixed.id).negotiable, false);

  // An offer on a fixed price is ignored
  const b1 = ok(await guest.c.rpc('book_slot', { p_slot: fixed.id, p_message: '', p_offer: 500 }), 'offer on fixed price');
  assert.equal(b1.price_egp, 1000);
  assert.equal(b1.offer_egp, null);

  // An offer on a negotiable price sets the price and the fee
  const b2 = ok(await other.c.rpc('book_slot', { p_slot: open.id, p_message: 'Can we do 800?', p_offer: 800 }), 'offer');
  assert.equal(b2.price_egp, 800);
  assert.equal(b2.offer_egp, 800);
  assert.equal(b2.fee_egp, 80);
  // Old two-argument calls still work
  const b3 = ok(await guest.c.rpc('book_slot', { p_slot: open.id, p_message: '' }), 'no offer');
  assert.equal(b3.price_egp, 1000);

  const reqs = ok(await host.c.rpc('get_slot_requests', { p_slot: open.id }), 'requests');
  assert.equal(reqs.find((r) => r.id === b2.id).offer_egp, 800, 'host sees the offer');

  // InstaPay only after acceptance
  let page = ok(await other.c.rpc('get_slot', { p_slot: open.id }), 'slot before acceptance')[0];
  assert.equal(page.host_instapay, null);
  await fails(other.c.rpc('mark_paid', { p_booking: b2.id }), 'not accepted', 'cannot mark paid before acceptance');
  ok(await host.c.rpc('respond_booking', { p_booking: b2.id, p_accept: true }), 'accept offer');
  page = ok(await other.c.rpc('get_slot', { p_slot: open.id }), 'slot after acceptance')[0];
  assert.equal(page.host_instapay, 'host@instapay');
  assert.equal(page.negotiable, true);
  const hostView = ok(await host.c.rpc('get_slot', { p_slot: open.id }), 'host view')[0];
  assert.equal(hostView.host_instapay, null, 'hosts are not shown their own InstaPay');

  // "I've paid"
  await fails(guest.c.rpc('mark_paid', { p_booking: b2.id }), 'not found', 'only the guest marks paid');
  const paid = ok(await other.c.rpc('mark_paid', { p_booking: b2.id }), 'mark paid');
  assert.ok(paid.paid_at);
  const again = ok(await other.c.rpc('mark_paid', { p_booking: b2.id }), 'mark paid twice');
  assert.equal(again.paid_at, paid.paid_at, 'second tap changes nothing');
  const after = ok(await host.c.rpc('get_slot_requests', { p_slot: open.id }), 'requests after paying');
  assert.ok(after.find((r) => r.id === b2.id).paid_at, 'host sees it was paid');
  const notes = ok(await host.c.from('notifications').select('type').eq('user_id', host.id).eq('type', 'booking_paid'), 'host notified');
  assert.equal(notes.length, 1);
});
