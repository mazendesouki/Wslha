// وصّلها — client-side helpers for the new session-management system
// (src/lib/session.ts / db/security-50-session-management.sql). Shared by
// every page that starts or ends a session (login.astro, register.astro,
// and the logout buttons in Nav.astro/profile.astro/settings.astro) so
// they don't each reimplement the same fetch calls.
//
// Both calls are best-effort and must never block or fail the existing
// localStorage-based flow (wslha_user) that the rest of the app still
// runs on — this is purely additive infrastructure, not a replacement.

export async function startServerSession(phone: string, password: string): Promise<void> {
  try {
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone, password }),
      // Lets the request finish (and its Set-Cookie header still get
      // applied) even if the page navigates away right after this call —
      // without it, a redirect scheduled a few hundred ms later can
      // cancel the fetch before the browser ever receives the cookie.
      keepalive: true,
    });
    if (!res.ok) return;
    const { accessToken, expiresIn } = await res.json();
    if (accessToken) {
      sessionStorage.setItem('wslha_access_token', accessToken);
      sessionStorage.setItem('wslha_access_token_exp', String(Date.now() + expiresIn * 1000));
    }
  } catch {
    /* best-effort */
  }
}

/**
 * Returns a currently-valid (not expired, 30s safety margin) access
 * token, refreshing it via /api/auth/refresh first if the cached one is
 * missing or stale. Returns null if there's no active session at all
 * (e.g. this browser logged in before the session system shipped, or the
 * refresh cookie is gone/expired/revoked) — callers must fall back to
 * whatever they did before this system existed in that case, not treat
 * null as an error.
 */
export async function getValidAccessToken(): Promise<string | null> {
  try {
    const token = sessionStorage.getItem('wslha_access_token');
    const expRaw = sessionStorage.getItem('wslha_access_token_exp');
    const exp = expRaw ? Number(expRaw) : 0;
    if (token && exp > Date.now() + 30_000) return token;
  } catch {
    /* sessionStorage unavailable — fall through to a fresh refresh attempt */
  }

  try {
    const res = await fetch('/api/auth/refresh', { method: 'POST' });
    if (!res.ok) return null;
    const { accessToken, expiresIn } = await res.json();
    if (!accessToken) return null;
    try {
      sessionStorage.setItem('wslha_access_token', accessToken);
      sessionStorage.setItem('wslha_access_token_exp', String(Date.now() + expiresIn * 1000));
    } catch {
      /* ignore — the token is still usable for this one call */
    }
    return accessToken;
  } catch {
    return null;
  }
}

export function endServerSession(): void {
  try {
    fetch('/api/auth/logout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      keepalive: true,
    }).catch(() => {});
  } catch {
    /* best-effort */
  }
  try {
    sessionStorage.removeItem('wslha_access_token');
    sessionStorage.removeItem('wslha_access_token_exp');
  } catch {
    /* ignore */
  }
}
