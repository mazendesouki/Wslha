// وصّلها — GET /api/history/orders
// Same access-token pattern as /api/wallet/*: returns orders belonging
// to the phone in the signed token — matched against BOTH
// customer_phone and driver_phone (rather than trusting a client-sent
// "role") so it's correct regardless of what role the caller claims to
// have; a phone can only ever match rows it actually owns either way.
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
  const res = await fetch(`${SB_URL}/rest/v1/orders?${filter}&order=created_at.desc&limit=100`, {
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}` },
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'orders_fetch_failed' }), { status: 502 });
  }
  const orders = await res.json();
  return new Response(JSON.stringify({ orders }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
