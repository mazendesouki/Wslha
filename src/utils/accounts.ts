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
      email:    acc.email?.toLowerCase()    || null,
      username: acc.username?.toLowerCase() || null,
      created_at: createdAt,
    };
    const res = await fetch(`${SB_URL}/rest/v1/accounts`, {
      method:  'POST',
      headers: { ...SB_H, Prefer: 'return=minimal' },
      body:    JSON.stringify(payload),
    });
    if (res.status === 409) return false; // unique constraint violation
    if (!res.ok) return 'error';
    return true;
  } catch { return 'error'; }
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
    const res = await fetch(
      `${SB_URL}/rest/v1/accounts?phone=eq.${encodeURIComponent(p)}&select=*&limit=1`,
      { headers: SB_H }
    );
    if (res.ok) {
      const rows = await res.json();
      if (!rows[0])                        return { ok: false, reason: 'not_found' };
      if (rows[0].password !== password)   return { ok: false, reason: 'bad_password' };
      return { ok: true, account: rows[0] };
    }
  } catch {}

  const account = lsAll().find(a => a.phone === p);
  if (!account)                      return { ok: false, reason: 'not_found' };
  if (account.password !== password) return { ok: false, reason: 'bad_password' };
  return { ok: true, account };
}

export function findAccount(phone: string): Account | undefined {
  return lsAll().find(a => a.phone === normalizeEgyptianPhone(phone));
}
