// وصّلها — GET /api/points/summary
// Same access-token pattern as /api/wallet/*: returns the loyalty
// points total + recent history for the phone in the signed token,
// never a client-supplied one. Single round trip (total + recent
// transactions together) since driver-dashboard.astro's wallet card
// always wants both at once.
import type { APIRoute } from 'astro';
import { verifyAccessToken, svc } from '../../../lib/session';
import { cached } from '../../../lib/redis';

export const prerender = false;

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

  // Cached 20s per (phone, limit) — this is read every time the wallet
  // card opens, but a loyalty-points balance doesn't move within a
  // 20-second window for any real user action, so a short cache here cuts
  // duplicate reads without ever showing data more than ~20s stale. Falls
  // through to the same two Supabase reads as before when Redis isn't
  // configured yet, or on any cache error — this never becomes the only
  // path to the data.
  //
  // Uses the service-role helper (svc), not the public anon/publishable
  // key: `points`/`point_transactions` have no SELECT grant for
  // anon/authenticated at all (confirmed via information_schema —
  // service_role and postgres only), so every request made with the
  // anon key was failing with a permission error on every single call,
  // 502-ing before Redis was ever reached. Safe here specifically
  // because `payload.sub` already came from a verified access token
  // above — the server, not the client, controls which phone gets
  // queried, same justification as session.ts's own auth_sessions reads.
  // Temporary — confirms a genuine cache HIT now that the fetchFailed bug
  // above (anon key had no SELECT grant) is fixed. Remove once Redis is
  // confirmed actually connecting end to end.
  let fetchFailed = false;
  let wasCacheMiss = false;
  const body = await cached(`points-summary:${payload.sub}:${limit}`, 20, async () => {
    wasCacheMiss = true;
    const [totalsRes, txRes] = await Promise.all([
      svc(`points?phone=eq.${phone}&select=total_points`),
      svc(`point_transactions?phone=eq.${phone}&select=points,type,created_at&order=created_at.desc&limit=${limit}`),
    ]);
    if (!totalsRes.ok || !txRes.ok) {
      fetchFailed = true;
      return null;
    }
    const totals = await totalsRes.json();
    const transactions = await txRes.json();
    const totalPoints = Array.isArray(totals) && totals[0] ? totals[0].total_points ?? 0 : 0;
    return { totalPoints, transactions };
  });

  console.log(`points-summary: ${wasCacheMiss ? 'cache MISS (fetched from Supabase)' : 'cache HIT (served from Redis)'} for ${payload.sub}, fetchFailed=${fetchFailed}`);

  if (fetchFailed || body === null) {
    return new Response(JSON.stringify({ error: 'points_fetch_failed' }), { status: 502 });
  }
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
