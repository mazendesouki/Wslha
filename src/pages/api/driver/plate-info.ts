// وصّلها — POST /api/driver/plate-info
// IDOR fix Phase 1 — see profile/driver-application.ts for rationale.
// update_driver_plate_info trusted a client-supplied p_phone, so
// anyone could overwrite another driver's registered plate number/
// photo. Phone now comes from the verified access token.
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
  const { vehicle_reg_number, plate_photo_url } = body || {};

  const res = await fetch(`${SB_URL}/rest/v1/rpc/update_driver_plate_info`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      p_phone: payload.sub,
      p_vehicle_reg_number: vehicle_reg_number ?? null,
      p_plate_photo_url: plate_photo_url ?? null,
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
