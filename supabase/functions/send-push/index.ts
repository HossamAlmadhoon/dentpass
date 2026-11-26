// Delivers DentPass notifications to members' phones (web push).
//
// POST { notification_id }  from the database when a notification is created.
//   It only sends notifications that are new and not yet sent, so a request
//   from anywhere else can't create or repeat anything.
// GET                        returns the public key the app needs to subscribe.
//
// Settings (Supabase secrets): VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, optional VAPID_CONTACT.
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2';

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
});

const publicKey = Deno.env.get('VAPID_PUBLIC_KEY') ?? '';
const privateKey = Deno.env.get('VAPID_PRIVATE_KEY') ?? '';
if (publicKey && privateKey) {
  webpush.setVapidDetails(`mailto:${Deno.env.get('VAPID_CONTACT') ?? 'support@dentpass.app'}`, publicKey, privateKey);
}

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, authorization, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

type Lang = 'ar' | 'en';
type Text = { title: string; body: string };

function message(type: string, title: string, lang: Lang): Text {
  const q = (s: string) => (lang === 'ar' ? `«${s}»` : `"${s}"`);
  const ar: Record<string, Text> = {
    booking_requested: { title: 'طلب جديد', body: `طلب جديد على ${q(title)}` },
    booking_accepted: { title: 'تم قبول طلبك', body: `تم قبول طلبك على ${q(title)}` },
    booking_declined: { title: 'تم رفض طلبك', body: `تم رفض طلبك على ${q(title)}` },
    booking_cancelled: { title: 'إلغاء حجز', body: `تم إلغاء حجز على ${q(title)}` },
    slot_updated: { title: 'تعديل موعد', body: `قام المضيف بتعديل ${q(title)}` },
    slot_cancelled: { title: 'إلغاء موعد', body: `تم إلغاء ${q(title)} من المضيف` },
    review_received: { title: 'تقييم جديد', body: `حصلت على تقييم جديد على ${q(title)}` },
    reminder: { title: 'تذكير', body: `موعدك ${q(title)} غدًا أو اليوم` },
    host_reminder: { title: 'تذكير', body: `أنت تستضيف ${q(title)} قريبًا` },
    new_slot: { title: 'موعد جديد قد يهمك', body: title },
    report_received: { title: 'بلاغ جديد', body: 'وصل بلاغ جديد للمراجعة' },
    verification_approved: { title: 'دنت باس', body: 'تم توثيق أوراقك. يمكنك الآن النشر' },
    verification_rejected: { title: 'دنت باس', body: 'لم نتمكن من توثيق بياناتك' },
    account_suspended: { title: 'دنت باس', body: 'تم إيقاف حسابك' },
    account_reinstated: { title: 'دنت باس', body: 'تم تفعيل حسابك مرة أخرى' },
  };
  const en: Record<string, Text> = {
    booking_requested: { title: 'New request', body: `New request on ${q(title)}` },
    booking_accepted: { title: 'Request accepted', body: `Your request for ${q(title)} was accepted` },
    booking_declined: { title: 'Request declined', body: `Your request for ${q(title)} was declined` },
    booking_cancelled: { title: 'Booking cancelled', body: `A booking on ${q(title)} was cancelled` },
    slot_updated: { title: 'Slot changed', body: `The host changed ${q(title)}` },
    slot_cancelled: { title: 'Slot cancelled', body: `${q(title)} was cancelled by the host` },
    review_received: { title: 'New rating', body: `You received a new rating for ${q(title)}` },
    reminder: { title: 'Reminder', body: `${q(title)} is coming up soon` },
    host_reminder: { title: 'Reminder', body: `You're hosting ${q(title)} soon` },
    new_slot: { title: 'A new slot for you', body: title },
    report_received: { title: 'New report', body: 'A new report is waiting for review' },
    verification_approved: { title: 'DentPass', body: 'You are verified. You can now post slots' },
    verification_rejected: { title: 'DentPass', body: "We couldn't approve your details" },
    account_suspended: { title: 'DentPass', body: 'Your account was suspended' },
    account_reinstated: { title: 'DentPass', body: 'Your account is active again' },
  };
  const table = lang === 'en' ? en : ar;
  return table[type] ?? { title: 'DentPass', body: title };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method === 'GET') {
    return Response.json({ publicKey }, { headers: cors });
  }
  if (!publicKey || !privateKey) return new Response('push keys not set', { status: 503, headers: cors });

  let id = '';
  try {
    id = String((await req.json()).notification_id ?? '');
  } catch {
    return new Response('bad request', { status: 400, headers: cors });
  }

  // Claim the notification: only new (last 10 minutes) and not yet sent
  const since = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { data: n } = await db
    .from('notifications')
    .update({ pushed_at: new Date().toISOString() })
    .eq('id', id)
    .is('pushed_at', null)
    .gte('created_at', since)
    .select('id, user_id, type, slot_title')
    .maybeSingle();
  if (!n) return new Response('nothing to send', { headers: cors });

  const { data: profile } = await db.from('profiles').select('lang').eq('id', n.user_id).maybeSingle();
  const text = message(n.type, n.slot_title ?? '', profile?.lang === 'en' ? 'en' : 'ar');
  const payload = JSON.stringify({ ...text, tag: n.type, url: './' });

  const { data: devices } = await db.from('push_subscriptions').select('id, endpoint, p256dh, auth').eq('user_id', n.user_id);
  let delivered = 0;
  for (const d of devices ?? []) {
    try {
      await webpush.sendNotification({ endpoint: d.endpoint, keys: { p256dh: d.p256dh, auth: d.auth } }, payload, {
        TTL: 24 * 60 * 60,
        urgency: 'high',
      });
      delivered++;
      await db.from('push_subscriptions').update({ last_used_at: new Date().toISOString() }).eq('id', d.id);
    } catch (e) {
      const status = (e as { statusCode?: number }).statusCode;
      // The phone unsubscribed or the app was removed: forget this device
      if (status === 404 || status === 410) await db.from('push_subscriptions').delete().eq('id', d.id);
    }
  }
  return Response.json({ delivered }, { headers: cors });
});
