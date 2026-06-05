import { normalizeEgyptianPhone } from './phone';

export type Role = 'customer' | 'driver';

export interface Account {
  phone: string;
  password: string;
  name: string;
  role: Role;
  city?: string;
  createdAt: string;
}

// ── Supabase config (anon/publishable key — safe for client) ──
const SB_URL = 'https://vtikgyiopkjnrwlqnmfx.supabase.co';
const SB_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';
const SB_HEADERS = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json' };

async function sbFind(phone: string): Promise<Account | null | 'error'> {
  try {
    const res = await fetch(
      `${SB_URL}/rest/v1/accounts?phone=eq.${encodeURIComponent(phone)}&select=*&limit=1`,
      { headers: SB_HEADERS }
    );
    if (!res.ok) return 'error';
    const rows = await res.json();
    return rows[0] ?? null;
  } catch { return 'error'; }
}

async function sbInsert(acc: Account): Promise<true | false | 'error'> {
  try {
    const res = await fetch(`${SB_URL}/rest/v1/accounts`, {
      method: 'POST',
      headers: { ...SB_HEADERS, Prefer: 'return=minimal' },
      body: JSON.stringify(acc),
    });
    if (res.status === 409) return false; // unique violation — duplicate phone
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

// ── Public API (async) ──

export async function addAccount(acc: Omit<Account, 'phone'> & { phone: string }): Promise<boolean> {
  const phone = normalizeEgyptianPhone(acc.phone);
  const record: Account = { ...acc, phone } as Account;

  const sbResult = await sbInsert(record);
  if (sbResult !== 'error') return sbResult; // true = success, false = duplicate

  // Supabase unavailable → localStorage
  const accounts = lsAll();
  if (accounts.some(a => a.phone === phone)) return false;
  lsSave([...accounts, record]);
  return true;
}

export type LoginResult =
  | { ok: true; account: Account }
  | { ok: false; reason: 'not_found' | 'bad_password' };

export async function verifyLogin(phone: string, password: string): Promise<LoginResult> {
  const p = normalizeEgyptianPhone(phone);

  const sbResult = await sbFind(p);
  if (sbResult !== 'error') {
    if (!sbResult)                       return { ok: false, reason: 'not_found' };
    if (sbResult.password !== password)  return { ok: false, reason: 'bad_password' };
    return { ok: true, account: sbResult };
  }

  // Supabase unavailable → localStorage
  const account = lsAll().find(a => a.phone === p);
  if (!account)                        return { ok: false, reason: 'not_found' };
  if (account.password !== password)   return { ok: false, reason: 'bad_password' };
  return { ok: true, account };
}

// kept for compatibility (sync, localStorage only — used by orders page etc.)
export function findAccount(phone: string): Account | undefined {
  return lsAll().find(a => a.phone === normalizeEgyptianPhone(phone));
}
