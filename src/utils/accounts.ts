// Client-side account store (localStorage simulation — no backend).
// Holds registered customers and drivers so login can reject unregistered users.
import { normalizeEgyptianPhone } from './phone';

export type Role = 'customer' | 'driver';

export interface Account {
  phone: string;      // normalized 01XXXXXXXXX
  password: string;
  name: string;
  role: Role;
  city?: string;
  createdAt: string;
}

const KEY = 'wslha_accounts';

export function getAccounts(): Account[] {
  try {
    return JSON.parse(localStorage.getItem(KEY) || '[]');
  } catch {
    return [];
  }
}

export function findAccount(phone: string): Account | undefined {
  const p = normalizeEgyptianPhone(phone);
  return getAccounts().find(a => a.phone === p);
}

// Adds an account. Returns false if the phone is already registered.
export function addAccount(acc: Omit<Account, 'phone'> & { phone: string }): boolean {
  const phone = normalizeEgyptianPhone(acc.phone);
  const accounts = getAccounts();
  if (accounts.some(a => a.phone === phone)) return false;
  accounts.push({ ...acc, phone });
  try {
    localStorage.setItem(KEY, JSON.stringify(accounts));
  } catch { /* storage unavailable */ }
  return true;
}

export type LoginResult =
  | { ok: true; account: Account }
  | { ok: false; reason: 'not_found' | 'bad_password' };

export function verifyLogin(phone: string, password: string): LoginResult {
  const account = findAccount(phone);
  if (!account) return { ok: false, reason: 'not_found' };
  if (account.password !== password) return { ok: false, reason: 'bad_password' };
  return { ok: true, account };
}
