-- ═══════════════════════════════════════════════════════════════
-- Admin-configurable pricing — phase 1 (manual control panel).
--
-- Every per-km rate / base fee / minimum fare for local + external rides
-- was hardcoded in guard_ride_fare() (db/rides-vehicle-pricing-v5-min-
-- fare-40.sql). This moves those numbers into app_settings (the same
-- key-value table commission rates already live in — see
-- security-07-commission-settlement.sql) so an admin can edit them from
-- admin.astro without a code deploy. Same defensive
-- nullif(...)::numeric + range-checked fallback pattern the commission
-- rate reads already use, so a missing/corrupt key never breaks pricing.
--
-- Airport pricing is NOT covered here — it has no server-side
-- recomputation at all (still client-trusted, see the comment at the
-- bottom of guard_ride_fare()), so its knobs are read client-side
-- directly from these same app_settings keys (web:
-- src/data/airports.ts loadPricingSettings(); Flutter:
-- core/pricing_settings.dart).
--
-- 'dynamic_pricing_enabled' is a placeholder for a later phase (surge
-- pricing based on live demand/supply) — stored now so the admin toggle
-- has somewhere to persist, but nothing reads it yet.
-- ═══════════════════════════════════════════════════════════════

insert into public.app_settings (key, value) values
  ('local_base_fee',     '25'),
  ('local_min_fare',     '40'),
  ('local_rate_sedan',   '8'),
  ('local_rate_suv',     '10.4'),
  ('local_rate_van',     '11.2'),
  ('external_base_fee',  '50'),
  ('external_min_fare',  '150'),
  ('external_rate_sedan','7'),
  ('external_rate_suv',  '9.1'),
  ('external_rate_van',  '9.8'),
  ('airport_base_fee',   '300'),
  ('airport_min_fare',   '2500'),
  ('airport_rate_sedan', '12'),
  ('airport_rate_suv',   '15.6'),
  ('airport_rate_van',   '16.8'),
  ('dynamic_pricing_enabled', 'false')
on conflict (key) do nothing;

-- Reads a numeric app_settings value, falling back to p_default if the key
-- is missing, empty, non-numeric, or outside [p_min, p_max] (either bound
-- optional). PL/pgSQL can't nest function definitions inside another
-- function body, so this has to be its own top-level function rather than
-- a local helper inside guard_ride_fare().
create or replace function public._pricing_setting_num(
  p_key text, p_default numeric, p_min numeric default null, p_max numeric default null
) returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
  v_raw text;
  v_val numeric;
begin
  select value into v_raw from public.app_settings where key = p_key;
  v_val := nullif(v_raw, '')::numeric;
  if v_val is null then return p_default; end if;
  if p_min is not null and v_val < p_min then return p_default; end if;
  if p_max is not null and v_val > p_max then return p_default; end if;
  return v_val;
end;
$$;

create or replace function public.guard_ride_fare()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_category text;
  v_mult     numeric;
  v_effrate  numeric;
  v_km       numeric;
  v_tiered   numeric;
  v_zone     record;
  v_raw      numeric;
  v_rate_local    numeric;
  v_rate_external numeric;
  v_local_base    numeric;
  v_local_min     numeric;
  v_external_base numeric;
  v_external_min  numeric;
begin
  select category into v_category from public.vehicle_rates where id = new.vehicle_model;
  if v_category is null then
    v_category := 'sedan';
  end if;

  v_mult := least(1.35, greatest(0.8, 1 + (coalesce(new.vehicle_year, 2022) - 2021) * 0.035));

  v_rate_local := case v_category
    when 'suv' then public._pricing_setting_num('local_rate_suv', 10.4, 0)
    when 'van' then public._pricing_setting_num('local_rate_van', 11.2, 0)
    else             public._pricing_setting_num('local_rate_sedan', 8, 0)
  end;
  v_rate_external := case v_category
    when 'suv' then public._pricing_setting_num('external_rate_suv', 9.1, 0)
    when 'van' then public._pricing_setting_num('external_rate_van', 9.8, 0)
    else             public._pricing_setting_num('external_rate_sedan', 7, 0)
  end;
  v_local_base    := public._pricing_setting_num('local_base_fee', 25, 0);
  v_local_min     := public._pricing_setting_num('local_min_fare', 40, 0);
  v_external_base := public._pricing_setting_num('external_base_fee', 50, 0);
  v_external_min  := public._pricing_setting_num('external_min_fare', 150, 0);

  if new.ride_type is null or new.ride_type = 'local' then
    v_effrate := v_rate_local * v_mult;

    v_km := coalesce(new.distance_km, 0);
    v_tiered := least(v_km, 3) * 1.15
              + least(greatest(v_km - 3, 0), 7) * 1.0
              + greatest(v_km - 10, 0) * 0.9;

    select * into v_zone from public.fare_zones z
     where new.to_area is not null and exists (
       select 1 from unnest(z.keywords) k where new.to_area ilike '%' || k || '%'
     )
     limit 1;

    v_raw := (v_local_base + v_tiered * v_effrate) * coalesce(v_zone.factor, 1) + coalesce(v_zone.surcharge, 0);
    new.fare := ceil(greatest(v_raw, v_local_min) / 5) * 5;

  elsif new.ride_type = 'external' then
    v_effrate := v_rate_external * v_mult;
    v_km := coalesce(new.distance_km, 0);
    v_raw := v_external_base + v_km * v_effrate;
    new.fare := ceil(greatest(v_raw, v_external_min) / 5) * 5;
  end if;
  -- ride_type='airport': يُحسب في الواجهة — بلا إعادة حساب هنا حالياً.
  return new;
end;
$$;

revoke all on function public._pricing_setting_num(text, numeric, numeric, numeric) from public;
grant execute on function public._pricing_setting_num(text, numeric, numeric, numeric) to anon, authenticated;
