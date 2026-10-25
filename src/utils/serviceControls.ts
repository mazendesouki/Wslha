// وصّلها — db/security-127's service_controls: the real on/off/scheduled
// switch for a major service, already enforced server-side (the actual
// booking/order/registration/etc. RPC or INSERT trigger rejects it
// outright when off). This helper is purely a UX improvement — showing
// "غير متاحة" up front instead of letting someone fill a whole form and
// only discover it's off at the final submit.
const SB_URL = 'https://vtikgyiopkjnrwlqnmfx.supabase.co';
const SB_KEY = 'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4';

// Fails open (true) on any network hiccup — same convention as
// core/feature_flags.dart — so a flaky connection never blocks a
// feature that's actually on.
export async function checkServiceActive(key: string): Promise<boolean> {
  try {
    const res = await fetch(`${SB_URL}/rest/v1/rpc/is_service_active`, {
      method: 'POST',
      headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_key: key }),
    });
    if (!res.ok) return true;
    return (await res.json()) !== false;
  } catch {
    return true;
  }
}
