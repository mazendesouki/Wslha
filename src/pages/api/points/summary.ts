// وصّلها — GET /api/points/summary
// Same access-token pattern as /api/wallet/*: returns the loyalty
// points total + recent history for the phone in the signed token,
// never a client-supplied one. Single round trip (total + recent
// transactions together) since driver-dashboard.astro's wallet card
// always wants both at once.
import type { APIRoute } from 'astro';
import { verifyAccessToken, SB_URL } from '../../../lib/session';

export const prerender = false;

const SB_ANON_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';
const SB_H = { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}` };

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

  const limitParam = parseInt(reqUrl.searchParams.get('limit') || '10', 10);
  const limit = Number.isFinite(limitParam) ? Math.min(Math.max(limitParam, 1), 100) : 10;
  const phone = encodeURIComponent(payload.sub);

  const [totalsRes, txRes] = await Promise.all([
    fetch(`${SB_URL}/rest/v1/points?phone=eq.${phone}&select=total_points`, { headers: SB_H }),
    fetch(`${SB_URL}/rest/v1/point_transactions?phone=eq.${phone}&select=points,type,created_at&order=created_at.desc&limit=${limit}`, { headers: SB_H }),
  ]);
  if (!totalsRes.ok || !txRes.ok) {
    return new Response(JSON.stringify({ error: 'points_fetch_failed' }), { status: 502 });
  }
  const totals = await totalsRes.json();
  const transactions = await txRes.json();
  const totalPoints = Array.isArray(totals) && totals[0] ? totals[0].total_points ?? 0 : 0;

  return new Response(JSON.stringify({ totalPoints, transactions }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
