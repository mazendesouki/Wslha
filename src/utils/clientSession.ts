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
