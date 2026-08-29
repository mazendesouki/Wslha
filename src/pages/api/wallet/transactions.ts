// وصّلها — GET /api/wallet/transactions
// Same pattern as /api/wallet/balance: the phone whose transaction
// history gets returned comes from the signed, server-verified access
// token (Authorization: Bearer <token>) — never from anything the
// client sends. wallet_transactions' own row-level policy is still the
// same phone-scoped-but-anon-callable shape it always was (other pages
// — driver-dashboard.astro, merchant-dashboard.astro, admin.astro —
// still read it directly and aren't migrated yet), so this route
// doesn't need a new RPC: it just makes sure the *filter* is the
// authenticated phone, not a client-supplied one.
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

  const url =
    `${SB_URL}/rest/v1/wallet_transactions?phone=eq.${encodeURIComponent(payload.sub)}` +
    `&select=amount,type,note,created_at&order=created_at.desc&limit=${limit}`;
  const res = await fetch(url, {
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}` },
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
