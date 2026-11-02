// وصّلها — GET /api/profile/emergency-contacts
// IDOR fix Phase 1 — see driver-application.ts for rationale. These are
// a third party's phone numbers the account holder added, so leaking
// them by guessing someone else's phone is a real privacy exposure.
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

  const res = await fetch(`${SB_URL}/rest/v1/rpc/list_emergency_contacts`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_phone: payload.sub }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'fetch_failed' }), { status: 502 });
  }
  const contacts = await res.json();
  return new Response(JSON.stringify({ contacts }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
