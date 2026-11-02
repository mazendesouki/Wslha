// وصّلها — GET /api/profile/addresses
// IDOR fix Phase 1 — see driver-application.ts for rationale. Phone
// (home/work saved addresses) comes from the verified access token.
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

  const res = await fetch(`${SB_URL}/rest/v1/rpc/list_saved_addresses`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_phone: payload.sub }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'fetch_failed' }), { status: 502 });
  }
  const addresses = await res.json();
  return new Response(JSON.stringify({ addresses }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
