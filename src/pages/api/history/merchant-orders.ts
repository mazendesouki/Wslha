// وصّلها — GET /api/history/merchant-orders
// Same access-token pattern as /api/history/orders|rides, but scoped by
// store ownership instead of customer_phone/driver_phone: a merchant's
// orders live under their store(s), not directly under their own phone
// column on the orders table. Resolves the caller's own store id(s) from
// their signed token's phone (stores.owner_phone — stores SELECT is still
// open to anon/authenticated, only UPDATE/DELETE got locked down in
// security-171) and returns that store's orders, newest first.
import type { APIRoute } from 'astro';
import { verifyAccessToken, SB_URL } from '../../../lib/session';

export const prerender = false;

const SB_ANON_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';
const SB_H = { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}` };

function localPhone(phone: string): string {
  return phone.startsWith('+20') ? '0' + phone.slice(3) : phone;
}
function intlPhone(phone: string): string {
  return phone.startsWith('0') ? '+20' + phone.slice(1) : phone;
}

export const GET: APIRoute = async ({ request, url }) => {
  const auth = request.headers.get('authorization');
  const token = auth?.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) {
    return new Response(JSON.stringify({ error: 'no_token' }), { status: 401 });
  }
  const payload = verifyAccessToken(token);
  if (!payload) {
    return new Response(JSON.stringify({ error: 'invalid_token' }), { status: 401 });
  }

  const intl = intlPhone(payload.sub);
  const local = localPhone(payload.sub);
  const storesFilter = `or=(owner_phone.eq.${encodeURIComponent(intl)},owner_phone.eq.${encodeURIComponent(local)})`;
  const storesRes = await fetch(`${SB_URL}/rest/v1/stores?${storesFilter}&select=id`, { headers: SB_H });
  if (!storesRes.ok) {
    return new Response(JSON.stringify({ error: 'stores_fetch_failed' }), { status: 502 });
  }
  const stores = await storesRes.json();
  const storeIds = Array.isArray(stores) ? stores.map((s: { id: string }) => s.id) : [];
  if (storeIds.length === 0) {
    return new Response(JSON.stringify({ orders: [] }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }

  const limit = Math.min(Number(url.searchParams.get('limit')) || 1000, 1000);
  const idList = storeIds.map((id) => encodeURIComponent(id)).join(',');
  const res = await fetch(`${SB_URL}/rest/v1/orders?store_id=in.(${idList})&order=created_at.desc&limit=${limit}`, { headers: SB_H });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'orders_fetch_failed' }), { status: 502 });
  }
  const orders = await res.json();
  return new Response(JSON.stringify({ orders }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
