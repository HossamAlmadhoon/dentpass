// Shared links: an open slot's basics are visible without signing in; private details are not.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const URL = process.env.API_URL;
const ANON = process.env.ANON_KEY || process.env.PUBLISHABLE_KEY;
const SERVICE = process.env.SERVICE_ROLE_KEY || process.env.SECRET_KEY;
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(URL, SERVICE, opts);
const run = `${Date.now()}v7`;
const inHours = (h) => new Date(Date.now() + h * 36e5).toISOString();

function ok({ error, data }, step) {
  if (error) throw new Error(`${step}: ${error.message}`);
  return data;
}

test('Shared slot links', async () => {
  const c = createClient(URL, ANON, opts);
  const { data } = await c.auth.signUp({ email: `host-${run}@example.com`, password: 'password123' });
  const id = data.user.id;
  ok(await service.from('profiles').update({
    full_name: `Dr Host ${run}`, phone: '01099990000', role: 'dentist', area: 'dokki', status: 'approved',
    syndicate_no: '1', card_path: `${id}/c.jpg`, id_path: `${id}/i.jpg`,
  }).eq('id', id), 'host');
  const s = ok(await c.from('slots').insert({
    host_id: id, title: `Shared ${run}`, description: 'Implant case', kind: 'observe', area: 'dokki', address: 'Secret 12',
    capacity: 3, price_egp: 500, need_role: null, photo_paths: [], starts_at: inHours(4), ends_at: inHours(6),
    lat: 30.0444, lng: 31.2357,
  }).select().single(), 'post');

  const guest = createClient(URL, ANON, opts); // not signed in
  const rows = ok(await guest.rpc('public_slot', { p_slot: s.id }), 'anonymous preview');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].title, `Shared ${run}`);
  assert.equal(rows[0].price_egp, 500);
  for (const hidden of ['address', 'host_phone', 'lat', 'lng', 'host_instapay', 'host_id']) {
    assert.ok(!(hidden in rows[0]), `${hidden} is not shared`);
  }
  const { error } = await guest.rpc('get_slot', { p_slot: s.id });
  assert.ok(error, 'the full slot still needs an account');

  ok(await c.from('slots').update({ is_open: false }).eq('id', s.id), 'close');
  assert.equal(ok(await guest.rpc('public_slot', { p_slot: s.id }), 'closed').length, 0, 'closed slots are not shared');
});
