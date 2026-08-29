// وصّلها — GET /api/history/rides — see api/history/orders.ts for the
// full explanation, same pattern applied to the rides table.
import type { APIRoute } from 'astro';
import { verifyAccessToken, SB_URL } from '../../../lib/session';

export const prerender = false;

const SB_ANON_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';

function localPhone(phone: string): string {
  return phone.startsWith('+20') ? '0' + phone.slice(3) : phone;
}
function intlPhone(phone: string): string {
  return phone.startsWith('0') ? '+20' + phone.slice(1) : phone;
}

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

  const intl = intlPhone(payload.sub);
  const local = localPhone(payload.sub);
  const filter =
    `or=(customer_phone.eq.${encodeURIComponent(intl)},customer_phone.eq.${encodeURIComponent(local)},` +
    `driver_phone.eq.${encodeURIComponent(intl)},driver_phone.eq.${encodeURIComponent(local)})`;
  const res = await fetch(`${SB_URL}/rest/v1/rides?${filter}&order=created_at.desc&limit=100`, {
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}` },
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'rides_fetch_failed' }), { status: 502 });
  }
  const rides = await res.json();
  return new Response(JSON.stringify({ rides }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
