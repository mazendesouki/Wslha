-- =====================================================================
--  وصّلها — تحديث التسعير: سعر ثابت للكيلومتر حسب نوع الرحلة وفئة السيارة
--  (يستبدل نظام السعر المتفاوت لكل موديل بالكامل) + خدمة الرحلات الخارجية
--
--  سعر الكيلومتر الأساسي (سيدان)، وSUV/الفان أعلى بنسبة ثابتة (+30% / +40%):
--    داخلي (داخل دمياط)          8  ج.م/كم  →  SUV 10.4  •  فان 11.2
--    خارجي (خارج محافظة دمياط)   25 ج.م/كم  →  SUV 32.5  •  فان 35
--    مطار (لسه بيُحسب في الواجهة فقط، بلا إعادة حساب هنا — زي ما كان)
--
--  عمود vehicle_rates.rate_per_km بقى غير مستخدم في حساب السعر (تُرك في
--  الجدول كمرجع تاريخي فقط) — نستخدم category بس من الجدول ده الآن.
--
--  ⚠️ يجب أن يطابق TRIP_RATES + externalFare + meterFare في src/data/airports.ts.
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

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
  -- سعر الكيلومتر الأساسي لكل فئة سيارة، لكل نوع رحلة (يطابق TRIP_RATES في airports.ts)
  v_rate_local    numeric;
  v_rate_external numeric;
begin
  select category into v_category from public.vehicle_rates where id = new.vehicle_model;
  if v_category is null then
    v_category := 'sedan'; -- موديل غير معروف → سعر السيدان القياسي
  end if;

  -- معامل السنة: تدرّج مستمر لكل سنة (يطابق yearMultiplier في airports.ts)
  v_mult := least(1.35, greatest(0.8, 1 + (coalesce(new.vehicle_year, 2022) - 2021) * 0.035));

  v_rate_local    := case v_category when 'suv' then 10.4 when 'van' then 11.2 else 8  end;
  v_rate_external := case v_category when 'suv' then 32.5 when 'van' then 35   else 25 end;

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
    new.fare := ceil(greatest(v_raw, 35) / 5) * 5;

  elsif new.ride_type = 'external' then
    v_effrate := v_rate_external * v_mult;
    v_km := coalesce(new.distance_km, 0);
    v_raw := 50 + v_km * v_effrate;
    new.fare := ceil(greatest(v_raw, 150) / 5) * 5;
  end if;
  -- ride_type='airport': تسعير مركّب (فئة + سنة + شنط + مرافقين + انتظار)
  -- يُحسب في الواجهة — بلا إعادة حساب هنا حالياً (زي ما كان).
  return new;
end;
$$;

drop trigger if exists trg_guard_ride_fare on public.rides;
create trigger trg_guard_ride_fare
  before insert on public.rides
  for each row execute function public.guard_ride_fare();
