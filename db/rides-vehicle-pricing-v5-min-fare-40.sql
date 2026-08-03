-- Raises the local-ride minimum fare from 35 to 40 ج.م, matching the same
-- change in the web (src/pages/rides.astro, src/data/rides.ts) and the
-- Flutter app (fare_calculator.dart). This is the server-side function that
-- actually determines what a rider is charged — see
-- ridesvehiclepricingv4.sql for the full formula this is based on;
-- only the minimum-fare floor changes here (35 → 40).

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
begin
  select category into v_category from public.vehicle_rates where id = new.vehicle_model;
  if v_category is null then
    v_category := 'sedan';
  end if;

  v_mult := least(1.35, greatest(0.8, 1 + (coalesce(new.vehicle_year, 2022) - 2021) * 0.035));

  v_rate_local    := case v_category when 'suv' then 10.4 when 'van' then 11.2 else 8 end;
  v_rate_external := case v_category when 'suv' then 9.1  when 'van' then 9.8  else 7 end;

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

    v_raw := (25 + v_tiered * v_effrate) * coalesce(v_zone.factor, 1) + coalesce(v_zone.surcharge, 0);
    new.fare := ceil(greatest(v_raw, 40) / 5) * 5;

  elsif new.ride_type = 'external' then
    v_effrate := v_rate_external * v_mult;
    v_km := coalesce(new.distance_km, 0);
    v_raw := 50 + v_km * v_effrate;
    new.fare := ceil(greatest(v_raw, 150) / 5) * 5;
  end if;
  -- ride_type='airport': يُحسب في الواجهة — بلا إعادة حساب هنا حالياً.
  return new;
end;
$$;
