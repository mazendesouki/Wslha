// وصّلها — دالة إرسال إشعارات Push حقيقية (Web Push + FCM للتطبيقات الأصلية)
// تُستدعى من تريجر قاعدة البيانات (pg_net) عند إنشاء رحلة/طلب جديد،
// وترسل إشعاراً حتى لو المتصفح/التطبيق مقفول.
//
// الأسرار المطلوبة (Edge Function Secrets):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY  — مفاتيح Web Push
//   PUSH_TRIGGER_SECRET                  — سر مشترك يمنع أي حد من إطلاق إشعارات
//   FCM_SERVICE_ACCOUNT_JSON             — (اختياري) JSON كامل لحساب خدمة Firebase،
//                                           لإرسال إشعارات لتطبيقات Flutter (device_tokens).
//                                           لو مش موجود، بيتجاهل إرسال FCM بهدوء.
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — متوفرة تلقائياً في بيئة الدوال
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2';

const VAPID_PUBLIC  = Deno.env.get('VAPID_PUBLIC_KEY')!;
const VAPID_PRIVATE = Deno.env.get('VAPID_PRIVATE_KEY')!;
const TRIGGER_SECRET = Deno.env.get('PUSH_TRIGGER_SECRET')!;
const FCM_SERVICE_ACCOUNT = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');

webpush.setVapidDetails('mailto:info@wslha.co', VAPID_PUBLIC, VAPID_PRIVATE);

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// ── FCM (HTTP v1) — Google's OAuth2 service-account flow, hand-rolled with
// Web Crypto since Deno edge functions can't use the Node-only firebase-admin SDK.
function base64url(input: string | ArrayBuffer): string {
  const str = typeof input === 'string' ? input : String.fromCharCode(...new Uint8Array(input));
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----BEGIN PRIVATE KEY-----/, '').replace(/-----END PRIVATE KEY-----/, '').replace(/\s+/g, '');
  const raw = atob(b64);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

let cachedFcmToken: { token: string; exp: number } | null = null;

async function getFcmAccessToken(): Promise<string | null> {
  if (!FCM_SERVICE_ACCOUNT) return null;
  const now = Math.floor(Date.now() / 1000);
  if (cachedFcmToken && cachedFcmToken.exp - 60 > now) return cachedFcmToken.token;

  try {
    const svc = JSON.parse(FCM_SERVICE_ACCOUNT);
    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claim = base64url(JSON.stringify({
      iss: svc.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }));
    const unsigned = `${header}.${claim}`;
    const key = await crypto.subtle.importKey(
      'pkcs8', pemToArrayBuffer(svc.private_key),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
    );
    const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));
    const jwt = `${unsigned}.${base64url(sig)}`;

    const res = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    });
    if (!res.ok) { console.error('[fcm] token exchange failed', res.status, await res.text().catch(() => '')); return null; }
    const json = await res.json();
    cachedFcmToken = { token: json.access_token, exp: now + (json.expires_in || 3600) };
    return json.access_token;
  } catch (e) {
    console.error('[fcm] token exchange error', e);
    return null;
  }
}

async function sendFcm(
  token: string, title: string, body: string, url: string, tag: string,
  type: string, channel: string,
): Promise<boolean> {
  const accessToken = await getFcmAccessToken();
  if (!accessToken || !FCM_SERVICE_ACCOUNT) return false;
  const projectId = JSON.parse(FCM_SERVICE_ACCOUNT).project_id;
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}` },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        // `type` lets the app react the instant a foreground message
        // arrives (e.g. re-check for a driver's dispatch offer) instead of
        // only showing a tray notification — see PushRegistrar.onMessage.
        data: { url, tag, type },
        android: { priority: 'high', notification: { tag, channel_id: channel } },
      },
    }),
  });
  if (!res.ok) console.error('[fcm] send failed', res.status, await res.text().catch(() => ''));
  return res.ok;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });
  if (req.headers.get('x-push-secret') !== TRIGGER_SECRET) {
    return new Response('forbidden', { status: 403 });
  }

  let payload: { target?: string; phone?: string; title?: string; body?: string; url?: string; tag?: string; type?: string; channel?: string };
  try { payload = await req.json(); } catch { return new Response('bad json', { status: 400 }); }

  const title   = payload.title   || 'وصّلها';
  const body    = payload.body    || '';
  const url     = payload.url     || '/';
  const tag     = payload.tag     || 'wslha';
  const type    = payload.type    || '';
  const channel = payload.channel || 'wslha_orders';

  // target: 'drivers' → كل السائقين المشتركين • phone محدد → شخص واحد
  let query = admin.from('push_subscriptions').select('id, phone, subscription');
  if (payload.phone) query = query.eq('phone', payload.phone);
  else query = query.eq('role', payload.target || 'driver');

  const { data: subs, error } = await query;
  if (error) return new Response('db error: ' + error.message, { status: 500 });

  const message = JSON.stringify({ title, body, url, tag });
  let sent = 0;
  const dead: string[] = [];

  await Promise.allSettled((subs || []).map(async (row) => {
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

  // FCM (تطبيقات Flutter الأصلية). device_tokens مفيهوش عمود "role" زي
  // push_subscriptions، فبالنسبة لبث جماعي (target بلا phone) بنجيب
  // أرقام أصحاب الدور ده من accounts الأول.
  let fcmSent = 0;
  let fcmTokens: { id: string; token: string }[] = [];
  if (payload.phone) {
    const { data } = await admin.from('device_tokens').select('id, token').eq('phone', payload.phone);
    fcmTokens = data || [];
  } else {
    const role = payload.target || 'driver';
    const { data: roleAccounts } = await admin.from('accounts').select('phone').eq('role', role);
    const phones = (roleAccounts || []).map((r) => r.phone).filter(Boolean);
    if (phones.length) {
      const { data } = await admin.from('device_tokens').select('id, token').in('phone', phones);
      fcmTokens = data || [];
    }
  }
  await Promise.allSettled(fcmTokens.map(async (d) => {
    if (await sendFcm(d.token, title, body, url, tag, type, channel)) fcmSent++;
    // ملاحظة: مش بنمسح التوكن الفاشل هنا — فشل FCM ممكن يكون مؤقت
    // (شبكة/انتهاء صلاحية access token)، مش بالضرورة توكن ميت زي
    // إشعارات المتصفح؛ تنظيف التوكنات المنتهية محتاج كود خطأ FCM محدد.
  }));

  return Response.json({ sent, cleaned: dead.length, fcmSent });
});
