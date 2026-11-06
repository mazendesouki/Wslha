// وصّلها — POST /api/push/register
// upsert_device_token trusted a client-supplied p_phone with no check at
// all — anyone could register their own device token against any victim's
// phone number, diverting that victim's push notifications to themselves
// (security-178). Same shape as /api/driver/location.ts (IDOR fix
// pattern): phone comes from the verified access token, never from the
// request body.
import type { APIRoute } from 'astro';
import { verifyAccessToken, SB_URL } from '../../../lib/session';

export const prerender = false;

const SB_ANON_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';

export const POST: APIRoute = async ({ request }) => {
  const auth = request.headers.get('authorization');
  const token = auth?.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) {
    return new Response(JSON.stringify({ error: 'no_token' }), { status: 401 });
  }
  const payload = verifyAccessToken(token);
  if (!payload) {
    return new Response(JSON.stringify({ error: 'invalid_token' }), { status: 401 });
  }

  let body: any;
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'invalid_body' }), { status: 400 });
  }
  const { fcm_token, platform } = body || {};
  if (typeof fcm_token !== 'string' || !fcm_token) {
    return new Response(JSON.stringify({ error: 'invalid_token_field' }), { status: 400 });
  }
  if (platform !== 'android' && platform !== 'ios') {
    return new Response(JSON.stringify({ error: 'invalid_platform' }), { status: 400 });
  }

  const res = await fetch(`${SB_URL}/rest/v1/rpc/upsert_device_token`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      p_phone: payload.sub,
      p_token: fcm_token,
      p_platform: platform,
    }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'register_failed' }), { status: 502 });
  }
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
