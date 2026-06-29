// Shared Supabase client WITH session management (Auth migration).
// Use this for anything that needs the signed-in user's session/JWT.
// The old anon-only `fetch(SB_URL, { headers: SB_H })` calls still work
// during the migration; they will be replaced phase by phase.
import { createClient } from '@supabase/supabase-js';

export const SB_URL = 'https://vtikgyiopkjnrwlqnmfx.supabase.co';
export const SB_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';

export const supabase = createClient(SB_URL, SB_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false,
    storageKey: 'wslha_auth',
  },
});

// Egyptian local (01XXXXXXXXX) → E.164 (+201XXXXXXXXX) for Supabase phone auth.
export function toE164(localOrAny: string): string {
  let p = (localOrAny || '').trim().replace(/\s+/g, '');
  if (p.startsWith('+')) return p;
  if (p.startsWith('00')) return '+' + p.slice(2);
  if (p.startsWith('01') && p.length === 11) return '+20' + p.slice(1);
  if (p.startsWith('201')) return '+' + p;
  return p;
}
