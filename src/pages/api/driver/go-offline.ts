// وصّلها — POST /api/driver/go-offline
// IDOR fix Phase 1 — see profile/driver-application.ts for rationale.
// set_driver_offline trusted a client-supplied p_driver_phone, so
// anyone could sabotage another driver's dispatch availability by
// forcing them offline. Phone now comes from the verified access
// token.
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

  const res = await fetch(`${SB_URL}/rest/v1/rpc/set_driver_offline`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_driver_phone: payload.sub }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'update_failed' }), { status: 502 });
  }
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
