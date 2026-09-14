-- ═══════════════════════════════════════════════════════════════
-- Activates the "التسعير الذكي الديناميكي (Surge)" feature —
-- app_settings.dynamic_pricing_enabled has existed since security-11 as
-- a placeholder admin toggle, but nothing ever read it. This wires it
-- up for real: when enabled, local/external ride fares get an automatic
-- multiplier based on live demand (pending rides in the last 15 min)
-- vs. supply (online drivers in the last 10 min).
--
-- Thresholds are a starting point, not a confirmed business number —
-- adjust freely:
--   demand/supply ratio  <1.2   → ×1.00 (no surge)
--                 1.2–2.0       → ×1.15
--                 2.0–3.0       → ×1.30
--                 ≥3.0          → ×1.50
-- ═══════════════════════════════════════════════════════════════

create or replace function public.current_surge_multiplier(p_ride_type text default 'local')
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_enabled boolean;
  v_demand  int;
  v_supply  int;
  v_ratio   numeric;
begin
  select coalesce(value, 'false') = 'true' into v_enabled
  from public.app_settings where key = 'dynamic_pricing_enabled';

  if not coalesce(v_enabled, false) then
    return 1.0;
  end if;

  select count(*) into v_demand
  from public.rides
  where status = 'pending'
    and (
      (p_ride_type = 'local' and (ride_type is null or ride_type = 'local'))
      or ride_type = p_ride_type
    )
    and created_at > now() - interval '15 minutes';

  select count(*) into v_supply
  from public.driver_locations
  where is_online = true
    and updated_at > now() - interval '10 minutes';

  if v_supply <= 0 then
    v_ratio := case when v_demand > 0 then 999 else 0 end;
  else
    v_ratio := v_demand::numeric / v_supply;
  end if;

  return case
    when v_ratio >= 3   then 1.50
    when v_ratio >= 2   then 1.30
    when v_ratio >= 1.2 then 1.15
    else 1.0
  end;
end;
$$;

revoke all on function public.current_surge_multiplier(text) from public;
grant execute on function public.current_surge_multiplier(text) to anon, authenticated;

-- guard_ride_fare(): combine the surge multiplier with the existing tier
-- multiplier (same order — before the min-fare floor, floor scaled too)
-- for local/external rides only, matching the client (fare_calculator.dart).
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
  v_surge_mult    numeric;
  v_combined_mult numeric;
begin
  select category into v_category from public.vehicle_rates where id = new.vehicle_model;
  if v_category is null then
    v_category := 'sedan';
  end if;

  v_mult := least(1.35, greatest(0.8, 1 + (coalesce(new.vehicle_year, 2022) - 2021) * 0.035));

  v_tier_mult := case coalesce(new.airport_quality_tier, 'regular')
    when 'ac'     then 1.25
    when 'clean'  then 1.15
    when 'modern' then 1.35
    else 1.0
  end;

  v_surge_mult := public.current_surge_multiplier(coalesce(new.ride_type, 'local'));
  v_combined_mult := v_tier_mult * v_surge_mult;

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

    v_raw := ((v_local_base + v_tiered * v_effrate) * coalesce(v_zone.factor, 1) + coalesce(v_zone.surcharge, 0)) * v_combined_mult;
    new.fare := ceil(greatest(v_raw, v_local_min * v_combined_mult) / 5) * 5;

  elsif new.ride_type = 'external' then
    v_effrate := v_rate_external * v_mult;
    v_km := coalesce(new.distance_km, 0);
    v_raw := (v_external_base + v_km * v_effrate) * v_combined_mult;
    new.fare := ceil(greatest(v_raw, v_external_min * v_combined_mult) / 5) * 5;
  end if;
  return new;
end;
$$;
