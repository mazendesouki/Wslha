// وصّلها — POST /api/auth/login
// Verifies phone+password (same verify_login RPC the client-side login
// flow already uses) and, on success, starts a new session family:
// issues a 15-minute access token in the JSON body and sets an HttpOnly
// refresh-token cookie. See db/security-50-session-management.sql and
// src/lib/session.ts for the design/scope notes.
import type { APIRoute } from 'astro';
import { SB_URL, createSession, refreshCookieHeader, requestMeta, ABSOLUTE_SESSION_SECONDS } from '../../../lib/session';

export const prerender = false;

const SB_ANON_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';

export const POST: APIRoute = async ({ request }) => {
  let body: { phone?: string; password?: string };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad_json' }), { status: 400 });
  }
  const phone = (body.phone || '').trim();
  const password = body.password || '';
  if (!phone || !password) {
    return new Response(JSON.stringify({ error: 'phone_and_password_required' }), { status: 400 });
  }

  const loginRes = await fetch(`${SB_URL}/rest/v1/rpc/verify_login`, {
    method: 'POST',
    headers: { apikey: SB_ANON_KEY, Authorization: `Bearer ${SB_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_phone: phone, p_password: password }),
  });
  if (!loginRes.ok) {
    return new Response(JSON.stringify({ error: 'login_failed' }), { status: 502 });
  }
  const rows = await loginRes.json();
  const account = Array.isArray(rows) && rows[0] ? rows[0] : null;
  if (!account) {
    return new Response(JSON.stringify({ error: 'invalid_credentials' }), { status: 401 });
  }

  try {
    const session = await createSession(account.phone, requestMeta(request));
    return new Response(
      JSON.stringify({ accessToken: session.accessToken, expiresIn: 15 * 60, account }),
      {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Set-Cookie': refreshCookieHeader(session.refreshToken, ABSOLUTE_SESSION_SECONDS),
        },
      },
    );
  } catch (e) {
    console.error('[api/auth/login] session creation failed', e);
    return new Response(JSON.stringify({ error: 'session_creation_failed' }), { status: 500 });
  }
};
