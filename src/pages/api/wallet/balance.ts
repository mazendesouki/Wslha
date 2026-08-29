// وصّلها — GET /api/wallet/balance
// First real feature migrated onto the session-management system's
// access token: the phone whose balance gets returned comes from the
// signed, server-verified token (Authorization: Bearer <token>) —
// never from anything the client sends directly. Anyone forging a
// request with someone else's phone number gets nothing; they'd need
// that person's actual token, which only src/pages/api/auth/login.ts
// issues after a real password check.
//
// get_my_wallet_balance itself (db/security-49-secure-wallets-and-addresses.sql)
// is already phone-scoped and safe to call with the anon key — the only
// thing this route adds is *which* phone gets passed to it.
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

  const res = await fetch(`${SB_URL}/rest/v1/rpc/get_my_wallet_balance`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_phone: payload.sub }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'balance_fetch_failed' }), { status: 502 });
  }
  const balance = await res.json();
  return new Response(JSON.stringify({ balance }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
