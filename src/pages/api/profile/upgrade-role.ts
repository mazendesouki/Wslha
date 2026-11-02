// وصّلها — POST /api/profile/upgrade-role
// IDOR fix Phase 1 — see profile/driver-application.ts for rationale.
// upgrade_account_role itself already whitelists p_role to 'driver'/
// 'merchant' only (can't reach 'admin'), so this was never a privilege-
// escalation path — but it still trusted a client-supplied p_phone, so
// anyone could flip another account's role + status to 'pending' with
// zero proof of ownership. Phone now comes from the verified token.
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
  const role = body?.role;
  if (role !== 'driver' && role !== 'merchant') {
    return new Response(JSON.stringify({ error: 'invalid_role' }), { status: 400 });
  }

  const res = await fetch(`${SB_URL}/rest/v1/rpc/upgrade_account_role`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_phone: payload.sub, p_role: role }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'upgrade_failed' }), { status: 502 });
  }
  const ok = await res.json();
  return new Response(JSON.stringify({ ok }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
