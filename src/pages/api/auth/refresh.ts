// وصّلها — POST /api/auth/refresh
// Reads the HttpOnly refresh-token cookie, rotates it (issuing a fresh
// 15-minute access token + a fresh refresh token), and re-sets the
// cookie. Reuse of an already-rotated token past its 5s grace window is
// treated as theft: the whole session family is revoked and a security
// alert is logged (see src/lib/session.ts's rotateSession()).
import type { APIRoute } from 'astro';
import { rotateSession, refreshCookieHeader, clearRefreshCookieHeader, readRefreshCookie, requestMeta } from '../../../lib/session';

export const prerender = false;

export const POST: APIRoute = async ({ request }) => {
  const refreshToken = readRefreshCookie(request);
  if (!refreshToken) {
    return new Response(JSON.stringify({ error: 'no_session' }), { status: 401 });
  }

  const result = await rotateSession(refreshToken, requestMeta(request));

  if (!result.ok) {
    // Every failure path clears the cookie client-side too — a dead or
    // compromised session shouldn't keep getting silently retried.
    return new Response(JSON.stringify({ error: result.reason }), {
      status: 401,
      headers: { 'Content-Type': 'application/json', 'Set-Cookie': clearRefreshCookieHeader() },
    });
  }

  const maxAge = Math.max(0, Math.floor((new Date(result.absoluteExpiresAt).getTime() - Date.now()) / 1000));
  return new Response(JSON.stringify({ accessToken: result.accessToken, expiresIn: 15 * 60 }), {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Set-Cookie': refreshCookieHeader(result.refreshToken, maxAge),
    },
  });
};
