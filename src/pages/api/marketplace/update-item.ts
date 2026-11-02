// وصّلها — POST /api/marketplace/update-item
// IDOR fix Phase 1 — see profile/driver-application.ts for rationale.
// update_own_marketplace_item already checks seller_phone against
// p_phone before allowing the update — but p_phone itself was just
// whatever the client claimed, so anyone could pass a victim's phone
// + that victim's real item_id and mark/remove/sell it as if they
// owned it. Phone now comes from the verified access token.
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
  const { item_id, status } = body || {};
  if (!item_id || !['sold', 'removed', 'active'].includes(status)) {
    return new Response(JSON.stringify({ error: 'invalid_input' }), { status: 400 });
  }

  const res = await fetch(`${SB_URL}/rest/v1/rpc/update_own_marketplace_item`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_phone: payload.sub, p_item_id: item_id, p_status: status }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'update_failed' }), { status: 502 });
  }
  const ok = await res.json();
  return new Response(JSON.stringify({ ok }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
