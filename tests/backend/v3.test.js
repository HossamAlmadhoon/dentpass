// Version 3 checks: reports, alerts, home summary, reminders, phone subscriptions, settings, terms.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const URL = process.env.API_URL;
const ANON = process.env.ANON_KEY || process.env.PUBLISHABLE_KEY;
const SERVICE = process.env.SERVICE_ROLE_KEY || process.env.SECRET_KEY;
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(URL, SERVICE, opts);
const run = `${Date.now()}v3`;

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
    full_name: `Dr ${name} ${run}`, phone: '01099990000', role: 'dentist', syndicate_no: '1', area: 'dokki',
    status: 'approved', card_path: `${id}/c.jpg`, id_path: `${id}/i.jpg`, ...extra,
  }).eq('id', id), `approve ${name}`);
  return { c, id, name };
}

const types = async (m) =>
  ok(await m.c.from('notifications').select('type, slot_id').eq('user_id', m.id), 'notifications');

test('DentPass version 3', async () => {
  const host = await member('host');
  const guest = await member('guest');
  const watcher = await member('watcher');
  const admin = await member('admin', { is_admin: true });

  // ---- Terms and language
  ok(await guest.c.from('profiles').update({ accepted_terms_at: new Date().toISOString(), lang: 'en' }).eq('id', guest.id), 'accept terms, choose English');
  await fails(guest.c.from('profiles').update({ lang: 'fr' }).eq('id', guest.id), 'check', 'only Arabic or English');

  // ---- Alerts: watcher wants Learn slots in Dokki
  ok(await watcher.c.from('slot_alerts').insert({ kinds: ['observe', 'course'], area: 'dokki' }), 'save an alert');
  await fails(watcher.c.from('slot_alerts').insert({ kinds: ['observe', 'course'], area: 'dokki' }), 'duplicate|unique', 'same alert twice');
  ok(await watcher.c.from('slot_alerts').insert({ kinds: null, area: null }), 'an everything alert');
  ok(await host.c.from('slot_alerts').insert({ kinds: null, area: null }), 'host alert (must not fire for own slots)');

  const slot = (fields) => ({
    host_id: host.id, description: '', area: 'dokki', address: '3 Tahrir St', capacity: 2, price_egp: 500,
    need_role: null, photo_paths: [], ...fields,
  });
  ok(await host.c.from('slots').insert(slot({ kind: 'observe', title: `Endo case ${run}`, starts_at: inHours(3), ends_at: inHours(6) })), 'post a Learn slot in Dokki');
  ok(await host.c.from('slots').insert(slot({ kind: 'rent', title: `Chair ${run}`, area: 'maadi', starts_at: inHours(48), ends_at: inHours(52) })), 'post a chair in Maadi');
  const feed = ok(await guest.c.rpc('get_feed', { p_host: host.id }), 'host slots');
  const endo = feed.find((s) => s.kind === 'observe');
  const chair = feed.find((s) => s.kind === 'rent');

  const watcherNotes = (await types(watcher)).filter((n) => n.type === 'new_slot');
  assert.equal(watcherNotes.filter((n) => n.slot_id === endo.id).length, 1, 'one alert per slot even with two matching alerts');
  assert.equal(watcherNotes.filter((n) => n.slot_id === chair.id).length, 1, 'the everything alert matched the chair');
  assert.equal((await types(host)).filter((n) => n.type === 'new_slot').length, 0, 'no alerts for your own slots');
  ok(await watcher.c.from('slot_alerts').delete().eq('area', 'dokki'), 'remove an alert');
  const left = ok(await watcher.c.from('slot_alerts').select('id'), 'my alerts');
  assert.equal(left.length, 1);
  const peek = ok(await guest.c.from('slot_alerts').select('id'), 'other people\'s alerts are private');
  assert.equal(peek.length, 0);

  // ---- Booking, home summary
  const b = ok(await guest.c.rpc('book_slot', { p_slot: endo.id, p_message: '' }), 'guest books');
  let hostHome = ok(await host.c.rpc('my_home'), 'host home');
  assert.equal(hostHome.waiting, 1, 'host sees one request waiting');
  assert.equal(hostHome.hosting_next.slot_id, endo.id);
  ok(await host.c.rpc('respond_booking', { p_booking: b.id, p_accept: true }), 'host accepts');
  const guestHome = ok(await guest.c.rpc('my_home'), 'guest home');
  assert.equal(guestHome.next.slot_id, endo.id, 'guest sees their next slot');
  assert.equal(guestHome.next.address, '3 Tahrir St');
  hostHome = ok(await host.c.rpc('my_home'), 'host home after accepting');
  assert.equal(hostHome.waiting, 0);
  assert.equal(hostHome.hosting_next.accepted, 1);

  // ---- Reminders: once each, only from the scheduler
  await fails(guest.c.rpc('send_reminders'), 'permission|not found|denied', 'members cannot trigger reminders');
  const first = ok(await service.rpc('send_reminders'), 'run reminders');
  assert.ok(first >= 2, `reminders sent: ${first}`);
  assert.ok((await types(guest)).some((n) => n.type === 'reminder' && n.slot_id === endo.id), 'guest reminded');
  assert.ok((await types(host)).some((n) => n.type === 'host_reminder' && n.slot_id === endo.id), 'host reminded');
  ok(await service.rpc('send_reminders'), 'run reminders again');
  assert.equal((await types(guest)).filter((n) => n.type === 'reminder' && n.slot_id === endo.id).length, 1, 'no repeat reminders');
  assert.equal((await types(host)).filter((n) => n.type === 'host_reminder').length, 1, 'the chair (nobody accepted) gets no reminder');

  // ---- Reports
  await fails(guest.c.from('reports').insert({ member_id: guest.id, reason: 'other' }), 'row-level security|policy', 'cannot report yourself');
  await fails(guest.c.from('reports').insert({ member_id: host.id, reason: 'spam' }), 'check', 'reason must be one of the list');
  ok(await guest.c.from('reports').insert({ member_id: host.id, slot_id: endo.id, reason: 'no_show', details: 'Clinic was closed' }), 'guest reports');
  await fails(guest.c.from('reports').insert({ member_id: host.id, reason: 'other', status: 'closed' }), 'row-level security|policy', 'cannot file a closed report');
  const mine = ok(await guest.c.from('reports').select('id'), 'my reports');
  assert.equal(mine.length, 1);
  const theirs = ok(await watcher.c.from('reports').select('id'), 'others cannot see reports');
  assert.equal(theirs.length, 0);
  assert.ok((await types(admin)).some((n) => n.type === 'report_received'), 'admins are told');
  await fails(guest.c.rpc('admin_reports', { p_status: 'open' }), 'admins only', 'report list is for admins');
  const open = ok(await admin.c.rpc('admin_reports', { p_status: 'open' }), 'admin reads reports');
  const report = open.find((r) => r.reporter_id === guest.id);
  assert.equal(report.member_name, `Dr host ${run}`);
  assert.equal(report.slot_title, `Endo case ${run}`);
  ok(await admin.c.from('reports').update({ status: 'closed', closed_at: new Date().toISOString() }).eq('id', report.id), 'admin closes it');
  const closed = ok(await admin.c.rpc('admin_reports', { p_status: 'closed' }), 'closed reports');
  assert.ok(closed.some((r) => r.id === report.id));

  // ---- Settings: admins change the fee and support number; others can't
  const before = ok(await guest.c.from('app_settings').select('fee_percent, support_whatsapp').single(), 'read settings');
  ok(await guest.c.from('app_settings').update({ fee_percent: 0 }).eq('id', true), 'a member\'s change is ignored');
  const still = ok(await guest.c.from('app_settings').select('fee_percent').single(), 'settings unchanged');
  assert.equal(Number(still.fee_percent), Number(before.fee_percent));
  ok(await admin.c.from('app_settings').update({ support_whatsapp: '01000000000' }).eq('id', true), 'admin sets support number');
  const after = ok(await guest.c.from('app_settings').select('support_whatsapp').single(), 'members see it');
  assert.equal(after.support_whatsapp, '01000000000');

  // ---- Phone subscriptions
  const endpoint = `https://push.example.com/${run}`;
  ok(await guest.c.rpc('save_push_subscription', { p_endpoint: endpoint, p_p256dh: 'key', p_auth: 'auth', p_lang: 'ar' }), 'save a device');
  await fails(guest.c.rpc('save_push_subscription', { p_endpoint: 'http://bad', p_p256dh: 'k', p_auth: 'a', p_lang: 'ar' }), 'bad endpoint', 'only https endpoints');
  assert.equal(ok(await guest.c.from('push_subscriptions').select('id'), 'my devices').length, 1);
  assert.equal(ok(await watcher.c.from('push_subscriptions').select('id'), 'other devices are private').length, 0);
  ok(await watcher.c.rpc('save_push_subscription', { p_endpoint: endpoint, p_p256dh: 'key2', p_auth: 'auth2', p_lang: 'en' }), 'same phone, new person');
  assert.equal(ok(await guest.c.from('push_subscriptions').select('id'), 'device moved away').length, 0);
  assert.equal(ok(await watcher.c.from('push_subscriptions').select('id'), 'device moved here').length, 1);
  // A new notification for someone with a device still saves normally (sending happens in the background)
  ok(await guest.c.rpc('cancel_booking', { p_booking: b.id }), 'cancel triggers a host notification');
  ok(await watcher.c.rpc('remove_push_subscription', { p_endpoint: endpoint }), 'remove device');
  assert.equal(ok(await watcher.c.from('push_subscriptions').select('id'), 'devices after removing').length, 0);
});
