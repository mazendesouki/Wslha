// وصّلها — Session management core (server-only — never import this from
// a client-side <script>, it reads secrets that must never reach the
// browser bundle).
//
// Implements refresh-token rotation with a 5s grace period and family-wide
// revocation on reuse-after-grace, per db/security-50-session-management.sql.
// This module is infrastructure only — see that file's header for the
// explicit scope note (not wired into the rest of the app's RPCs yet).
import { createHmac, randomBytes, createHash, timingSafeEqual } from 'node:crypto';

export const SB_URL = 'https://vtikgyiopkjnrwlqnmfx.supabase.co';

// Never falls back to a hardcoded default — a missing secret must fail
// closed (every request 500s) rather than silently sign tokens with a
// guessable key.
function requireEnv(name: string): string {
  const v = import.meta.env[name];
  if (!v) throw new Error(`Missing required env var: ${name} (set it in the Vercel project's Environment Variables)`);
  return v;
}

const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;       // 15 minutes
const REFRESH_GRACE_SECONDS = 5;                 // race-condition grace window
const ABSOLUTE_SESSION_DAYS = 30;                // hard ceiling per family

export const REFRESH_COOKIE_NAME = 'wslha_rt';
export const REFRESH_COOKIE_PATH = '/api/auth';

// ── Service-role Supabase REST helper — bypasses RLS/grants entirely,
//    the only thing allowed to touch auth_sessions/security_alerts
//    (both are `revoke all from anon, authenticated`). ──────────────────
async function svc(path: string, init: RequestInit = {}): Promise<Response> {
  const key = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
  return fetch(`${SB_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
}

// ── Access token: compact HS256 JWT, stateless (no DB row) ─────────────
function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export interface AccessTokenPayload {
  sub: string; // account phone
  family_id: string;
  iat: number;
  exp: number;
}

export function signAccessToken(phone: string, familyId: string): string {
  const secret = requireEnv('SESSION_JWT_SECRET');
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payload: AccessTokenPayload = { sub: phone, family_id: familyId, iat: now, exp: now + ACCESS_TOKEN_TTL_SECONDS };
  const body = base64url(JSON.stringify(payload));
  const signature = base64url(createHmac('sha256', secret).update(`${header}.${body}`).digest());
  return `${header}.${body}.${signature}`;
}

/** Returns the verified payload, or null if the token is malformed, mis-signed, or expired. */
export function verifyAccessToken(token: string): AccessTokenPayload | null {
  try {
    const secret = requireEnv('SESSION_JWT_SECRET');
    const [header, body, signature] = token.split('.');
    if (!header || !body || !signature) return null;
    const expected = base64url(createHmac('sha256', secret).update(`${header}.${body}`).digest());
    const a = Buffer.from(signature);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
    const payload: AccessTokenPayload = JSON.parse(Buffer.from(body, 'base64').toString('utf8'));
    if (payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

// ── Refresh token: opaque random value; only its sha256 hash is stored ──
function newRefreshToken(): string {
  return randomBytes(32).toString('base64url');
}
function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export interface RequestMeta {
  ip: string | null;
  userAgent: string | null;
}
export function requestMeta(request: Request): RequestMeta {
  return {
    ip: request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || null,
    userAgent: request.headers.get('user-agent') || null,
  };
}

/** Starts a brand-new session (fresh family) — call this on successful login. */
export async function createSession(phone: string, meta: RequestMeta) {
  const familyId = crypto.randomUUID();
  const refreshToken = newRefreshToken();
  const absoluteExpiresAt = new Date(Date.now() + ABSOLUTE_SESSION_DAYS * 86400 * 1000).toISOString();

  const res = await svc('auth_sessions', {
    method: 'POST',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({
      family_id: familyId,
      account_phone: phone,
      token_hash: hashToken(refreshToken),
      status: 'active',
      absolute_expires_at: absoluteExpiresAt,
      ip: meta.ip,
      user_agent: meta.userAgent,
    }),
  });
  if (!res.ok) throw new Error(`createSession insert failed: ${res.status} ${await res.text()}`);

  return {
    accessToken: signAccessToken(phone, familyId),
    refreshToken,
    familyId,
    absoluteExpiresAt,
  };
}

type RotateResult =
  | { ok: true; accessToken: string; refreshToken: string; absoluteExpiresAt: string }
  | { ok: false; reason: 'not_found' | 'expired' | 'family_revoked' | 'reuse_detected' };

/**
 * Validates + rotates a refresh token. Handles the 5s grace window (a
 * token already rotated but still inside its grace period is accepted
 * and simply re-issues the same successor pair, so two near-simultaneous
 * requests from the same browser tab don't race each other into a false
 * "reuse" verdict) and reuse-after-grace (revokes the whole family and
 * logs a security_alerts row + best-effort push).
 */
export async function rotateSession(refreshToken: string, meta: RequestMeta): Promise<RotateResult> {
  const tokenHash = hashToken(refreshToken);
  const rows = await svc(`auth_sessions?token_hash=eq.${tokenHash}&select=*`).then((r) => (r.ok ? r.json() : []));
  const row = Array.isArray(rows) && rows[0] ? rows[0] : null;
  if (!row) return { ok: false, reason: 'not_found' };

  const now = Date.now();
  if (new Date(row.absolute_expires_at).getTime() < now) {
    await revokeFamily(row.family_id, 'absolute_expiry');
    return { ok: false, reason: 'expired' };
  }

  if (row.status === 'revoked') {
    // Family already dead (e.g. a prior reuse detection, or explicit
    // logout) — this itself isn't new evidence of an attack, just a
    // stale client retrying, so no fresh alert here.
    return { ok: false, reason: 'family_revoked' };
  }

  if (row.status === 'rotated') {
    const graceOk = row.grace_expires_at && new Date(row.grace_expires_at).getTime() >= now;
    if (graceOk && row.replaced_by) {
      // Within the grace window — hand back the SAME successor that was
      // already issued, rather than rotating again, so a duplicate
      // concurrent request doesn't itself get treated as reuse next time.
      const successorRows = await svc(`auth_sessions?id=eq.${row.replaced_by}&select=*`).then((r) => (r.ok ? r.json() : []));
      const successor = Array.isArray(successorRows) && successorRows[0] ? successorRows[0] : null;
      if (successor && successor.status !== 'revoked') {
        // We don't have the successor's plaintext refresh token (only its
        // hash is stored) — mint the caller a fresh one atop the SAME row
        // by rotating forward from the successor instead of from `row`.
        return rotateSession_fromRow(successor, meta);
      }
    }
    // Outside the grace window (or successor missing/revoked) — someone
    // is replaying an already-rotated token. Treat as theft.
    await revokeFamily(row.family_id, 'refresh_token_reuse');
    await logSecurityAlert(row.account_phone, row.family_id, 'refresh_token_reuse', { ip: meta.ip, userAgent: meta.userAgent });
    return { ok: false, reason: 'reuse_detected' };
  }

  // status === 'active' — the normal, expected path.
  return rotateSession_fromRow(row, meta);
}

async function rotateSession_fromRow(row: any, meta: RequestMeta): Promise<RotateResult> {
  const newToken = newRefreshToken();
  const newId = crypto.randomUUID();

  const insertRes = await svc('auth_sessions', {
    method: 'POST',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({
      id: newId,
      family_id: row.family_id,
      account_phone: row.account_phone,
      token_hash: hashToken(newToken),
      status: 'active',
      absolute_expires_at: row.absolute_expires_at,
      ip: meta.ip,
      user_agent: meta.userAgent,
    }),
  });
  if (!insertRes.ok) throw new Error(`rotate insert failed: ${insertRes.status} ${await insertRes.text()}`);

  // Only mark the row we rotated FROM as 'rotated' with a grace window —
  // if it was already 'rotated' (the grace-window branch above), leave
  // its own row untouched and just extend nothing; the caller already
  // holds a token whose predecessor is being re-served.
  if (row.status === 'active') {
    const graceExpiresAt = new Date(Date.now() + REFRESH_GRACE_SECONDS * 1000).toISOString();
    await svc(`auth_sessions?id=eq.${row.id}`, {
      method: 'PATCH',
      headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({ status: 'rotated', grace_expires_at: graceExpiresAt, replaced_by: newId }),
    });
  }

  return {
    ok: true,
    accessToken: signAccessToken(row.account_phone, row.family_id),
    refreshToken: newToken,
    absoluteExpiresAt: row.absolute_expires_at,
  };
}

/** Looks up which family a refresh token (by its hash) belongs to, for logout's fallback path. */
export async function readFamilyIdForToken(refreshToken: string): Promise<string | null> {
  const tokenHash = hashToken(refreshToken);
  const rows = await svc(`auth_sessions?token_hash=eq.${tokenHash}&select=family_id`).then((r) => (r.ok ? r.json() : []));
  return Array.isArray(rows) && rows[0] ? rows[0].family_id : null;
}

export async function revokeFamily(familyId: string, reason: string) {
  await svc(`auth_sessions?family_id=eq.${familyId}&status=neq.revoked`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ status: 'revoked', revoked_at: new Date().toISOString(), revoked_reason: reason }),
  });
}

async function logSecurityAlert(phone: string, familyId: string, kind: string, detail: Record<string, unknown>) {
  await svc('security_alerts', {
    method: 'POST',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ account_phone: phone, family_id: familyId, kind, detail }),
  }).catch(() => {});

  // Best-effort real notification via the existing send-push edge
  // function — never let a failure here affect the security response
  // (the security_alerts row above is the durable record either way).
  const pushSecret = import.meta.env.PUSH_TRIGGER_SECRET;
  if (!pushSecret) return;
  try {
    await fetch(`${SB_URL}/functions/v1/send-push`, {
      method: 'POST',
      headers: { 'x-push-secret': pushSecret, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        phone,
        title: '⚠️ محاولة دخول مشبوهة',
        body: 'تم اكتشاف استخدام غير طبيعي لجلسة تسجيل الدخول بتاعتك، وتم إنهاء كل الجلسات النشطة لحسابك. لو مكنتش إنت، غيّر كلمة المرور فورًا.',
        tag: 'security-alert',
      }),
    });
  } catch {
    /* best-effort */
  }
}

export function refreshCookieHeader(value: string, maxAgeSeconds: number): string {
  const parts = [
    `${REFRESH_COOKIE_NAME}=${value}`,
    `Path=${REFRESH_COOKIE_PATH}`,
    'HttpOnly',
    'Secure',
    'SameSite=Strict',
    `Max-Age=${Math.max(0, Math.floor(maxAgeSeconds))}`,
  ];
  return parts.join('; ');
}

export function clearRefreshCookieHeader(): string {
  return `${REFRESH_COOKIE_NAME}=; Path=${REFRESH_COOKIE_PATH}; HttpOnly; Secure; SameSite=Strict; Max-Age=0`;
}

export function readRefreshCookie(request: Request): string | null {
  const cookieHeader = request.headers.get('cookie') || '';
  const match = cookieHeader.split(';').map((s) => s.trim()).find((s) => s.startsWith(`${REFRESH_COOKIE_NAME}=`));
  return match ? decodeURIComponent(match.slice(REFRESH_COOKIE_NAME.length + 1)) : null;
}

export const ABSOLUTE_SESSION_SECONDS = ABSOLUTE_SESSION_DAYS * 86400;
