import { normalizeEgyptianPhone } from './phone';

export type Role = 'customer' | 'driver';

export interface Account {
  phone:     string;
  password:  string;
  name:      string;
  username?: string;
  email?:    string;
  role:      Role;
  city?:     string;
  createdAt: string;
}

const SB_URL = 'https://vtikgyiopkjnrwlqnmfx.supabase.co';
const SB_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';
const SB_H   = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json' };

// ── Check if a field value is already taken in Supabase ──
export async function fieldExists(
  field: 'phone' | 'email' | 'username',
  value: string,
): Promise<boolean | 'error'> {
  if (!value) return false;
  try {
    const v = field === 'phone' ? normalizeEgyptianPhone(value) : value.trim().toLowerCase();
    const col = field === 'email' ? `email=ilike.${encodeURIComponent(v)}`
              : field === 'username' ? `username=ilike.${encodeURIComponent(v)}`
              : `phone=eq.${encodeURIComponent(v)}`;
    const res = await fetch(
      `${SB_URL}/rest/v1/accounts?${col}&select=phone&limit=1`,
      { headers: SB_H }
    );
    if (!res.ok) return 'error';
    const rows = await res.json();
    return Array.isArray(rows) && rows.length > 0;
  } catch { return 'error'; }
}

async function sbInsert(acc: Account): Promise<true | false | 'error'> {
  try {
    const { createdAt, ...rest } = acc;
    const payload = {
      ...rest,
      email:      acc.email?.toLowerCase()    || null,
      username:   acc.username?.toLowerCase() || null,
      created_at: createdAt,
    };
    const res = await fetch(`${SB_URL}/rest/v1/accounts`, {
      method:  'POST',
      headers: { ...SB_H, Prefer: 'return=minimal' },
      body:    JSON.stringify(payload),
    });
    if (res.status === 409) return false; // unique constraint violation
    if (!res.ok) {
      // Log for debugging without crashing
      res.text().then(t => console.warn('[accounts] sbInsert failed', res.status, t)).catch(() => {});
      return 'error';
    }
    return true;
  } catch (e) {
    console.warn('[accounts] sbInsert exception', e);
    return 'error';
  }
}

// ── localStorage fallback ──
const LS_KEY = 'wslha_accounts';

function lsAll(): Account[] {
  try { return JSON.parse(localStorage.getItem(LS_KEY) || '[]'); } catch { return []; }
}
function lsSave(accounts: Account[]): void {
  try { localStorage.setItem(LS_KEY, JSON.stringify(accounts)); } catch {}
}

// ── Public API ──

export async function addAccount(
  acc: Omit<Account, 'phone'> & { phone: string }
): Promise<boolean> {
  const phone  = normalizeEgyptianPhone(acc.phone);
  const record: Account = { ...acc, phone };

  const sbResult = await sbInsert(record);
  if (sbResult !== 'error') return sbResult;

  // Supabase unavailable → localStorage (phone-only uniqueness)
  const accounts = lsAll();
  if (accounts.some(a => a.phone === phone)) return false;
  lsSave([...accounts, record]);
  return true;
}

export type LoginResult =
  | { ok: true;  account: Account }
  | { ok: false; reason: 'not_found' | 'bad_password' };

export async function verifyLogin(phone: string, password: string): Promise<LoginResult> {
  const p = normalizeEgyptianPhone(phone);
  try {
    // Server-side verification: the password is checked inside Postgres
    // (bcrypt) and is NEVER sent back to the browser.
    const res = await fetch(`${SB_URL}/rest/v1/rpc/verify_login`, {
      method: 'POST',
      headers: SB_H,
      body: JSON.stringify({ p_phone: p, p_password: password }),
    });
    if (res.ok) {
      const rows = await res.json();
      const raw = Array.isArray(rows) ? rows[0] : rows;
      if (raw && raw.phone) {
        const account: Account = {
          phone:     raw.phone,
          password:  '',                      // never stored/echoed client-side
          name:      raw.name,
          username:  raw.username,
          email:     raw.email,
          role:      raw.role,
          city:      raw.city,
          createdAt: raw.created_at ?? raw.createdAt,
        };
        return { ok: true, account };
      }
      // RPC returned no row → either wrong password or unknown number.
      // Distinguish by checking existence (without reading the password).
      try {
        const ex = await fetch(
          `${SB_URL}/rest/v1/accounts?phone=eq.${encodeURIComponent(p)}&select=phone&limit=1`,
          { headers: SB_H }
        );
        const exRows = ex.ok ? await ex.json() : [];
        return { ok: false, reason: (exRows && exRows.length) ? 'bad_password' : 'not_found' };
      } catch {
        return { ok: false, reason: 'bad_password' };
      }
    }
  } catch {}

  // localStorage fallback (covers accounts saved locally when Supabase was down)
  const account = lsAll().find(a => a.phone === p);
  if (!account) return { ok: false, reason: 'not_found' };
  if (account.password !== password) return { ok: false, reason: 'bad_password' };
  return { ok: true, account };
}

export function findAccount(phone: string): Account | undefined {
  return lsAll().find(a => a.phone === normalizeEgyptianPhone(phone));
}
