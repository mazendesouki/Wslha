-- Applies the cost-based suggested pricing worked out in chat — run once
-- in the Supabase SQL Editor. Safe to re-run (plain upsert).
--
-- Assumptions behind these numbers (fuel 17 ج.م/لتر, driver net profit
-- 45 ج.م/ساعة محلي و70 ج.م/ساعة خارجي/مطار, معامل رجوع فاضي ×1.8
-- للخارجي/المطار) — see chat for the full derivation. Airport's min_fare
-- stays 2500 (already set) — at the new sedan rate (5), Cairo/Alexandria
-- naturally land AT that floor since their raw distance cost comes out
-- below it, while farther airports (Sharm, Hurghada, Luxor, Aswan) scale
-- above it by real distance — no per-airport special-case needed.

update public.app_settings set value = v.value, updated_at = now()
from (values
  ('local_base_fee',     '15'),
  ('local_min_fare',     '35'),
  ('local_rate_sedan',   '4.5'),
  ('local_rate_suv',     '5.5'),
  ('local_rate_van',     '6'),
  ('external_base_fee',  '40'),
  ('external_min_fare',  '150'),
  ('external_rate_sedan','6.5'),
  ('external_rate_suv',  '8.5'),
  ('external_rate_van',  '9.5'),
  ('airport_base_fee',   '300'),
  ('airport_min_fare',   '2500'),
  ('airport_rate_sedan', '5'),
  ('airport_rate_suv',   '7'),
  ('airport_rate_van',   '8')
) as v(key, value)
where app_settings.key = v.key;

select key, value from public.app_settings
where key in (
  'local_base_fee','local_min_fare','local_rate_sedan','local_rate_suv','local_rate_van',
  'external_base_fee','external_min_fare','external_rate_sedan','external_rate_suv','external_rate_van',
  'airport_base_fee','airport_min_fare','airport_rate_sedan','airport_rate_suv','airport_rate_van'
)
order by key;
