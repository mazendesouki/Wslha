-- ═══════════════════════════════════════════════════════════════
-- Fixes: picking a quality tier (نظيفة/مكيّفة/موديل حديث) had no visible
-- effect on price for most local trips. Since security-58 restored the
-- (now admin-lowered) base_fee/rate values from app_settings, the raw
-- fare for a typical short local trip falls below the local_min_fare
-- floor even after the tier multiplier is applied — so every tier
-- collapses to the exact same floored number and the customer sees no
-- difference between "عادية" and "موديل حديث".
--
-- Fix: scale the floor itself by the tier multiplier (same order as the
-- client's fare_calculator.dart), so a pricier tier is always at least
-- v_local_min * v_tier_mult, never just v_local_min regardless of tier.
-- ═══════════════════════════════════════════════════════════════

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
  v_tier_mult     numeric;
begin
  select category into v_category from public.vehicle_rates where id = new.vehicle_model;
  if v_category is null then
    v_category := 'sedan';
  end if;

  v_mult := least(1.35, greatest(0.8, 1 + (coalesce(new.vehicle_year, 2022) - 2021) * 0.035));

  v_tier_mult := case coalesce(new.airport_quality_tier, 'regular')
    when 'ac'     then 1.12
    when 'clean'  then 1.08
    when 'modern' then 1.20
    else 1.0
  end;

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

    v_raw := ((v_local_base + v_tiered * v_effrate) * coalesce(v_zone.factor, 1) + coalesce(v_zone.surcharge, 0)) * v_tier_mult;
    new.fare := ceil(greatest(v_raw, v_local_min * v_tier_mult) / 5) * 5;

  elsif new.ride_type = 'external' then
    v_effrate := v_rate_external * v_mult;
    v_km := coalesce(new.distance_km, 0);
    v_raw := (v_external_base + v_km * v_effrate) * v_tier_mult;
    new.fare := ceil(greatest(v_raw, v_external_min * v_tier_mult) / 5) * 5;
  end if;
  -- ride_type='airport': يُحسب في الواجهة — بلا إعادة حساب هنا حالياً.
  return new;
end;
$$;
