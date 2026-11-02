// وصّلها — GET /api/profile/driver-application
// IDOR fix Phase 1 (security-157 scoping plan): get_my_driver_application
// is phone-keyed but trusted the client-supplied phone with no proof of
// ownership — it returns national ID/license/photos. Same pattern as
// /api/wallet/balance: the phone comes from the signed, server-verified
// access token, never from the client. The underlying RPC itself is
// unchanged and still reachable directly by the Flutter apps (Phase 2
// migrates them onto this route; Phase 3 revokes the direct grant once
// they have).
import type { APIRoute } from 'astro';
import { verifyAccessToken, SB_URL } from '../../../lib/session';

export const prerender = false;

const SB_ANON_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';

export const GET: APIRoute = async ({ request }) => {
  const auth = request.headers.get('authorization');
  const token = auth?.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) {
    return new Response(JSON.stringify({ error: 'no_token' }), { status: 401 });
  }
  const payload = verifyAccessToken(token);
  if (!payload) {
    return new Response(JSON.stringify({ error: 'invalid_token' }), { status: 401 });
  }

  const res = await fetch(`${SB_URL}/rest/v1/rpc/get_my_driver_application`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_phone: payload.sub }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'fetch_failed' }), { status: 502 });
  }
  const rows = await res.json();
  return new Response(JSON.stringify({ application: Array.isArray(rows) ? rows[0] ?? null : null }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
