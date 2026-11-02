// وصّلها — GET /api/support/messages?conversation_id=...
// IDOR fix Phase 1 — see profile/driver-application.ts for rationale.
// get_support_messages itself already joins on c.user_phone = p_phone,
// so a conversation_id alone can't leak someone else's conversation —
// but it still trusted a client-supplied p_phone to pick WHICH user's
// conversation to check against. This route pins that to the verified
// token instead.
import type { APIRoute } from 'astro';
import { verifyAccessToken, SB_URL } from '../../../lib/session';

export const prerender = false;

const SB_ANON_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';

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

  const conversationId = reqUrl.searchParams.get('conversation_id');
  if (!conversationId) {
    return new Response(JSON.stringify({ error: 'conversation_id_required' }), { status: 400 });
  }

  const res = await fetch(`${SB_URL}/rest/v1/rpc/get_support_messages`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_conversation_id: conversationId, p_phone: payload.sub }),
  });
  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'fetch_failed' }), { status: 502 });
  }
  const messages = await res.json();
  return new Response(JSON.stringify({ messages }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
};
