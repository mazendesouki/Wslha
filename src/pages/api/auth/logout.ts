// وصّلها — POST /api/auth/logout
// Revokes every token in the session's family (not just the current
// refresh token) and clears the cookie, so any other tab/device holding
// an older-but-still-valid refresh token in the same family is logged
// out too.
import type { APIRoute } from 'astro';
import { revokeFamily, clearRefreshCookieHeader, readRefreshCookie, verifyAccessToken, readFamilyIdForToken } from '../../../lib/session';

export const prerender = false;

export const POST: APIRoute = async ({ request }) => {
  const refreshToken = readRefreshCookie(request);
  let familyId: string | null = null;

  // The access token (if the caller sends one) names the family directly.
  // Falling back to it means logout still works even if the refresh
  // cookie was already lost/cleared client-side.
  const auth = request.headers.get('authorization');
  if (auth?.startsWith('Bearer ')) {
    const payload = verifyAccessToken(auth.slice(7));
    if (payload) familyId = payload.family_id;
  }

  if (!familyId && refreshToken) {
    // No access token given — look the family up by the refresh token's
    // own row instead of trusting anything client-supplied.
    familyId = await readFamilyIdForToken(refreshToken);
  }

  if (familyId) {
    await revokeFamily(familyId, 'logout');
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json', 'Set-Cookie': clearRefreshCookieHeader() },
  });
};
