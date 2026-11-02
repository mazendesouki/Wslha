// وصّلها — POST /api/driver/location
// IDOR fix Phase 1 — see profile/driver-application.ts for rationale.
// upsert_driver_location trusted a client-supplied p_driver_phone, so
// anyone could spoof another driver's live location (or flip their
// online/offline flag) shown to customers and dispatch. Phone now
// comes from the verified access token. This endpoint is called
// frequently during an active trip, so it's deliberately minimal —
// no extra round-trips beyond the token check and the RPC itself.
//
// is_online must stay optional/null-passthrough, not default to true:
// the RPC's own default (p_is_online DEFAULT NULL) means "preserve
// whatever's already stored" via `coalesce(excluded.is_online,
// driver_locations.is_online)` — a plain GPS ping while already
// online omits this field on purpose, and forcing it to true would
// silently bring an offline driver back online on every ping.
import type { APIRoute } from 'astro';
import { verifyAccessToken, SB_URL } from '../../../lib/session';

export const prerender = false;

const SB_ANON_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';

export const POST: APIRoute = async ({ request }) => {
  const auth = request.headers.get('authorization');
  const token = auth?.startsWith('Bearer ') ? auth.slice(7) : null;
  if (!token) {
    return new Response(JSON.stringify({ error: 'no_token' }), { status: 401 });
  }
  const payload = verifyAccessToken(token);
  if (!payload) {
    return new Response(JSON.stringify({ error: 'invalid_token' }), { status: 401 });
  }

  let body: any;
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'invalid_body' }), { status: 400 });
  }
  const { lat, lng, driver_name, heading, is_online } = body || {};
  if (typeof lat !== 'number' || typeof lng !== 'number') {
    return new Response(JSON.stringify({ error: 'invalid_coordinates' }), { status: 400 });
  }

  const res = await fetch(`${SB_URL}/rest/v1/rpc/upsert_driver_location`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      p_driver_phone: payload.sub,
      p_lat: lat,
      p_lng: lng,
      p_driver_name: driver_name ?? null,
      p_heading: typeof heading === 'number' ? heading : null,
      p_is_online: typeof is_online === 'boolean' ? is_online : null,
    }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'update_failed' }), { status: 502 });
  }
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
