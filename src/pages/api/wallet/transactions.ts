// وصّلها — GET /api/wallet/transactions
// Same pattern as /api/wallet/balance: the phone whose transaction
// history gets returned comes from the signed, server-verified access
// token (Authorization: Bearer <token>) — never from anything the
// client sends. wallet_transactions SELECT is locked down for anon/
// authenticated (security-124 — it had no filter at all and dumped
// every user's financial history), so this now goes through
// get_my_wallet_transactions, still filtered by the authenticated
// phone, not a client-supplied one.
import type { APIRoute } from 'astro';
import { verifyAccessToken, SB_URL } from '../../../lib/session';

export const prerender = false;

const SB_ANON_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';

export const GET: APIRoute = async ({ request, url: reqUrl }) => {
  const auth = request.headers.get('authorization');
  const token = auth?.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) {
    return new Response(JSON.stringify({ error: 'no_token' }), { status: 401 });
  }
  const payload = verifyAccessToken(token);
  if (!payload) {
    return new Response(JSON.stringify({ error: 'invalid_token' }), { status: 401 });
  }

  const limitParam = parseInt(reqUrl.searchParams.get('limit') || '50', 10);
  const limit = Number.isFinite(limitParam) ? Math.min(Math.max(limitParam, 1), 100) : 50;

  const res = await fetch(`${SB_URL}/rest/v1/rpc/get_my_wallet_transactions`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_phone: payload.sub, p_limit: limit }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'transactions_fetch_failed' }), { status: 502 });
  }
  const transactions = await res.json();
  return new Response(JSON.stringify({ transactions }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
