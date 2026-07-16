// وصّلها — دالة إرسال إشعارات Web Push حقيقية
// تُستدعى من تريجر قاعدة البيانات (pg_net) عند إنشاء رحلة جديدة،
// وترسل إشعاراً لكل السائقين المشتركين حتى لو التطبيق مقفول.
//
// الأسرار المطلوبة (Edge Function Secrets):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY  — مفاتيح Web Push
//   PUSH_TRIGGER_SECRET                  — سر مشترك يمنع أي حد من إطلاق إشعارات
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — متوفرة تلقائياً في بيئة الدوال
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2';

const VAPID_PUBLIC  = Deno.env.get('VAPID_PUBLIC_KEY')!;
const VAPID_PRIVATE = Deno.env.get('VAPID_PRIVATE_KEY')!;
const TRIGGER_SECRET = Deno.env.get('PUSH_TRIGGER_SECRET')!;

webpush.setVapidDetails('mailto:info@wslha.co', VAPID_PUBLIC, VAPID_PRIVATE);

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });
  if (req.headers.get('x-push-secret') !== TRIGGER_SECRET) {
    return new Response('forbidden', { status: 403 });
  }

  let payload: { target?: string; phone?: string; title?: string; body?: string; url?: string; tag?: string };
  try { payload = await req.json(); } catch { return new Response('bad json', { status: 400 }); }

  const title = payload.title || 'وصّلها';
  const body  = payload.body  || '';
  const url   = payload.url   || '/';
  const tag   = payload.tag   || 'wslha';

  // target: 'drivers' → كل السائقين المشتركين • phone محدد → شخص واحد
  let query = admin.from('push_subscriptions').select('id, phone, subscription');
  if (payload.phone) query = query.eq('phone', payload.phone);
  else query = query.eq('role', payload.target || 'driver');

  const { data: subs, error } = await query;
  if (error) return new Response('db error: ' + error.message, { status: 500 });
  if (!subs?.length) return Response.json({ sent: 0 });

  const message = JSON.stringify({ title, body, url, tag });
  let sent = 0;
  const dead: string[] = [];

  await Promise.allSettled(subs.map(async (row) => {
    try {
      await webpush.sendNotification(row.subscription, message);
      sent++;
    } catch (e) {
      // 404/410 = الاشتراك اتلغى من المتصفح — نظّفه من الجدول
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) dead.push(row.id);
    }
  }));

  if (dead.length) await admin.from('push_subscriptions').delete().in('id', dead);

  return Response.json({ sent, cleaned: dead.length });
});
