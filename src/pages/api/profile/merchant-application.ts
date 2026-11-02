// وصّلها — GET /api/profile/merchant-application
// IDOR fix Phase 1 — see driver-application.ts in this same directory
// for the full rationale; identical pattern, just the merchant-side
// RPC (business documents instead of driver license/national ID).
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

  const res = await fetch(`${SB_URL}/rest/v1/rpc/get_my_merchant_application`, {
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
