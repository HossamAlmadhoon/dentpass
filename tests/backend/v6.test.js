// v6: guests pay the listed price; the host owes DentPass a share of accepted bookings, settled monthly.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const URL = process.env.API_URL;
const ANON = process.env.ANON_KEY || process.env.PUBLISHABLE_KEY;
const SERVICE = process.env.SERVICE_ROLE_KEY || process.env.SECRET_KEY;
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(URL, SERVICE, opts);
const run = `${Date.now()}v6`;

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
  host_id: host.id, title: `Fees ${run}`, description: '', kind: 'observe', area: 'dokki', address: '3 Tahrir St',
  capacity: 5, price_egp: 1000, need_role: null, photo_paths: [], starts_at: inHours(3), ends_at: inHours(5), ...fields,
});
const monthOf = (iso) => {
  const d = new Date(new Date(iso).toLocaleString('en-US', { timeZone: 'Africa/Cairo' }));
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
};

test('Host fees', async () => {
  const settings = ok(await service.from('app_settings').select('fee_percent').single(), 'settings');
  assert.equal(Number(settings.fee_percent), 0, 'the pilot starts free');

  const host = await member('host');
  const admin = await member('admin', { is_admin: true });
  const a = await member('a');
  const b = await member('b');
  const c = await member('c');

  const s = ok(await host.c.from('slots').insert(slot(host)).select().single(), 'post');
  const month = monthOf(s.starts_at);

  // Free pilot: accepting costs the host nothing
  const free = ok(await a.c.rpc('book_slot', { p_slot: s.id, p_message: '' }), 'book during pilot');
  ok(await host.c.rpc('respond_booking', { p_booking: free.id, p_accept: true }), 'accept during pilot');
  let row = ok(await service.from('bookings').select('fee_egp, price_egp').eq('id', free.id).single(), 'pilot booking');
  assert.equal(row.fee_egp, 0);
  assert.equal(row.price_egp, 1000, 'the guest pays the listed price');
  await fails(host.c.rpc('mark_fees_paid', { p_month: month }), 'nothing owed', 'nothing to pay while free');

  // Admin turns on a 5% host fee: only bookings accepted from now on owe it
  ok(await admin.c.from('app_settings').update({ fee_percent: 5, instapay_handle: 'dentpass@instapay' }).eq('id', true), 'admin sets fee');
  try {
    const paid = ok(await b.c.rpc('book_slot', { p_slot: s.id, p_message: '' }), 'book with fee on');
    const accepted = ok(await host.c.rpc('respond_booking', { p_booking: paid.id, p_accept: true }), 'accept with fee on');
    assert.equal(accepted.fee_egp, 50);
    assert.equal(accepted.price_egp, 1000);

    const declined = ok(await c.c.rpc('book_slot', { p_slot: s.id, p_message: '' }), 'third request');
    const no = ok(await host.c.rpc('respond_booking', { p_booking: declined.id, p_accept: false }), 'decline');
    assert.equal(no.fee_egp, 0, 'declined requests owe nothing');

    // Host statement for the month
    let stmt = ok(await host.c.rpc('host_statement'), 'statement').find((m) => m.month === month);
    assert.equal(stmt.bookings, 2);
    assert.equal(stmt.earned_egp, 2000);
    assert.equal(stmt.fee_egp, 50);
    assert.equal(stmt.host_paid_at, null);

    // A guest who cancels removes the fee
    ok(await b.c.rpc('cancel_booking', { p_booking: paid.id }), 'guest cancels');
    stmt = ok(await host.c.rpc('host_statement'), 'statement after cancel').find((m) => m.month === month);
    assert.equal(stmt.fee_egp, 0);
    ok(await b.c.rpc('book_slot', { p_slot: s.id, p_message: 'back' }), 'books again');
    const again = ok(await service.from('bookings').select('id').eq('slot_id', s.id).eq('user_id', b.id).single(), 'find');
    ok(await host.c.rpc('respond_booking', { p_booking: again.id, p_accept: true }), 'accept again');

    // Host marks the month paid; admin sees it and confirms
    ok(await host.c.rpc('mark_fees_paid', { p_month: month }), 'host pays');
    await fails(a.c.rpc('admin_fees'), 'admins only', 'members cannot see all fees');
    const list = ok(await admin.c.rpc('admin_fees'), 'admin list').filter((r) => r.host_id === host.id);
    assert.equal(list.length, 1);
    assert.equal(list[0].fee_egp, 50);
    assert.ok(list[0].host_paid_at);
    assert.equal(list[0].confirmed_at, null);
    await fails(host.c.rpc('confirm_fees', { p_host: host.id, p_month: month }), 'admins only', 'hosts cannot confirm');
    ok(await admin.c.rpc('confirm_fees', { p_host: host.id, p_month: month }), 'admin confirms');
    stmt = ok(await host.c.rpc('host_statement'), 'statement after confirm').find((m) => m.month === month);
    assert.ok(stmt.confirmed_at);
    const others = ok(await a.c.from('fee_settlements').select('*'), 'other members see no settlements');
    assert.equal(others.length, 0);
  } finally {
    await service.from('app_settings').update({ fee_percent: 0 }).eq('id', true);
  }
});
