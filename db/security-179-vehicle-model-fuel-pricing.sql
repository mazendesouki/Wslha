-- =====================================================================
--  وصّلها — #179: تسعير المشاوير المحلية/الخارجية حسب موديل السيارة
--  المختارة فعليًا (مش فئة ثابتة) + تكلفة وقود حقيقية + مطابقة فئة
--  السائق عند القبول
--
--  guard_ride_fare() (db/security-11-pricing-settings.sql) بيقرا
--  new.vehicle_model و new.vehicle_year من قبل، بس ملهومش قيمة حقيقية
--  أبدًا للمشاوير المحلية/الخارجية (مفيش شاشة اختيار سيارة أصلاً) —
--  فبيفترض sedan/2022 دايمًا. الشغل هنا:
--
--  1) إضافة km_per_liter لجدول vehicle_rates (29 موديل موجودين بالفعل)
--     — قيم تقريبية واقعية حسب الموديل، مش دقة مصنع.
--  2) إضافة app_settings.fuel_price_per_liter (إعداد جديد قابل للتعديل
--     من لوحة الأدمن، نفس نمط local_base_fee وغيرها).
--  3) تعديل guard_ride_fare(): فضل نفس معادلة المسافة+الفئة+السنة
--     الموجودة، وبإضافة مكوّن تكلفة وقود حقيقي:
--       fuel_cost = (distance_km / km_per_liter) × fuel_price_per_liter
--     بيتضاف فوق الإجمالي قبل تقريب الحد الأدنى.
--  4) accept_dispatch_offer(): المشاوير المحلية/الخارجية دلوقتي كمان
--     بتتحقق إن فئة سيارة السائق المعتمدة (driver_applications.
--     vehicle_category) بتطابق فئة الموديل اللي العميل اختاره عند
--     الحجز (مشتقة من vehicle_model عبر vehicle_rates) — لو
--     vehicle_model فاضي (حجز قديم أو لسه الواجهة ملحقتش تتحدث)، مفيش
--     تحقق زي ما كان بالظبط (توافق خلفي كامل).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.vehicle_rates add column if not exists km_per_liter numeric;

update public.vehicle_rates set km_per_liter = case id
  -- sedan
  when 'mg5'          then 15.5
  when 'bmw3'         then 12.5
  when 'peugeot301'   then 16.0
  when 'corolla'      then 16.5
  when 'logan'        then 15.5
  when 'octavia'      then 14.0
  when 'optra'        then 13.5
  when 'fiattipo'     then 15.0
  when 'cerato'       then 14.5
  when 'mercc'        then 11.5
  when 'sunny'        then 16.0
  when 'elantra'      then 15.0
  -- suv
  when 'mgzs'         then 13.0
  when 'landcruiser'  then 6.5
  when 'grandcherokee' then 8.0
  when 'compass'      then 11.0
  when 'tiggo8'       then 9.5
  when 'sportage'     then 11.5
  when 'pajero'       then 8.5
  when 'xtrail'       then 11.0
  when 'patrol'       then 6.0
  when 'tucson'       then 11.5
  when 'creta'        then 13.5
  -- van
  when 'traveller'    then 9.5
  when 'hiace'        then 9.0
  when 'carnival'     then 10.0
  when 'sprinter'     then 8.5
  when 'xpander'      then 13.5
  when 'h1'           then 9.5
  else km_per_liter
end
where km_per_liter is null;

alter table public.vehicle_rates alter column km_per_liter set not null;

insert into public.app_settings (key, value) values
  ('fuel_price_per_liter', '13.5')
on conflict (key) do nothing;

create or replace function public.guard_ride_fare()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_category     text;
  v_km_per_liter numeric;
  v_mult         numeric;
  v_effrate      numeric;
  v_km           numeric;
  v_tiered       numeric;
  v_zone         record;
  v_raw          numeric;
  v_fuel_cost    numeric;
  v_fuel_price   numeric;
  v_rate_local    numeric;
  v_rate_external numeric;
  v_local_base    numeric;
  v_local_min     numeric;
  v_external_base numeric;
  v_external_min  numeric;
begin
  select category, km_per_liter into v_category, v_km_per_liter
    from public.vehicle_rates where id = new.vehicle_model;
  if v_category is null then
    v_category := 'sedan';
  end if;

  v_mult := least(1.35, greatest(0.8, 1 + (coalesce(new.vehicle_year, 2022) - 2021) * 0.035));
  v_fuel_price := public._pricing_setting_num('fuel_price_per_liter', 13.5, 0);

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

    v_fuel_cost := case when v_km_per_liter > 0 then (v_km / v_km_per_liter) * v_fuel_price else 0 end;

    v_raw := (v_local_base + v_tiered * v_effrate) * coalesce(v_zone.factor, 1) + coalesce(v_zone.surcharge, 0) + v_fuel_cost;
    new.fare := ceil(greatest(v_raw, v_local_min) / 5) * 5;

  elsif new.ride_type = 'external' then
    v_effrate := v_rate_external * v_mult;
    v_km := coalesce(new.distance_km, 0);
    v_fuel_cost := case when v_km_per_liter > 0 then (v_km / v_km_per_liter) * v_fuel_price else 0 end;
    v_raw := v_external_base + v_km * v_effrate + v_fuel_cost;
    new.fare := ceil(greatest(v_raw, v_external_min) / 5) * 5;
  end if;
  -- ride_type='airport': يُحسب في الواجهة — بلا إعادة حساب هنا حالياً.
  return new;
end;
$$;

-- مطابقة فئة سيارة السائق مع الفئة اللي العميل اختارها عند الحجز —
-- نفس نمط airport_vehicle_category الموجود بالفعل، بس مشتقة من
-- vehicle_model للمشاوير المحلية/الخارجية بدل عمود منفصل.
create or replace function public.accept_dispatch_offer(p_offer_id text, p_driver_phone text, p_driver_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_offer public.dispatch_offers;
  v_row   jsonb;
  v_required_cat   text;
  v_required_tier  text;
  v_ride_model     text;
  v_driver_cat     text;
  v_driver_has_ac  boolean;
  v_driver_is_clean boolean;
  v_driver_is_modern boolean;
  v_tier_ok        boolean;
begin
  select * into v_offer
  from public.dispatch_offers
  where id::text = p_offer_id and driver_phone::text = p_driver_phone
  for update;

  if not found or v_offer.status <> 'pending' or v_offer.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'expired_or_taken');
  end if;

  if v_offer.target_type = 'ride' then
    select vehicle_category into v_driver_cat
    from public.driver_applications
    where phone::text = p_driver_phone
    order by created_at desc
    limit 1;

    if v_driver_cat in ('motorcycle', 'cargo', 'box_truck', 'flatbed') then
      update public.dispatch_offers set status = 'rejected', responded_at = now() where id::text = p_offer_id;
      return jsonb_build_object('ok', false, 'reason', 'delivery_only_vehicle');
    end if;

    select airport_vehicle_category, airport_quality_tier, vehicle_model
      into v_required_cat, v_required_tier, v_ride_model
    from public.rides
    where id::text = v_offer.target_id;

    -- مشاوير محلية/خارجية: لو العميل اختار موديل عند الحجز، فئته هي
    -- المطلوبة (airport_vehicle_category فاضي دايمًا هنا أصلاً).
    if v_required_cat is null and v_ride_model is not null then
      select category into v_required_cat from public.vehicle_rates where id = v_ride_model;
    end if;

    if v_required_cat is not null or v_required_tier is not null then
      select vehicle_category, has_ac, is_clean, is_modern
        into v_driver_cat, v_driver_has_ac, v_driver_is_clean, v_driver_is_modern
      from public.driver_applications
      where phone::text = p_driver_phone and status = 'approved'
      order by created_at desc
      limit 1;

      if v_required_cat is not null and v_driver_cat is distinct from v_required_cat then
        update public.dispatch_offers set status = 'rejected', responded_at = now() where id::text = p_offer_id;
        return jsonb_build_object('ok', false, 'reason', 'vehicle_category_mismatch');
      end if;

      if v_required_tier is not null then
        v_tier_ok := case v_required_tier
          when 'ac'      then coalesce(v_driver_has_ac, false)
          when 'clean'   then coalesce(v_driver_is_clean, false)
          when 'modern'  then coalesce(v_driver_is_modern, false)
          when 'regular' then not coalesce(v_driver_has_ac, false) and not coalesce(v_driver_is_clean, false) and not coalesce(v_driver_is_modern, false)
          else true
        end;

        if not v_tier_ok then
          update public.dispatch_offers set status = 'rejected', responded_at = now() where id::text = p_offer_id;
          return jsonb_build_object('ok', false, 'reason', 'quality_tier_mismatch');
        end if;
      end if;
    end if;

    update public.rides
       set status = 'accepted', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), accepted_at = now()
     where id::text = v_offer.target_id and driver_phone is null
     returning to_jsonb(rides.*) into v_row;
  else
    if not public.driver_eligible_for_order(p_driver_phone, v_offer.target_id) then
      update public.dispatch_offers set status = 'rejected', responded_at = now() where id::text = p_offer_id;
      return jsonb_build_object('ok', false, 'reason', 'vehicle_category_mismatch');
    end if;

    update public.orders
       set status = 'on_the_way', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), picked_up_at = null
     where id::text = v_offer.target_id and driver_phone is null and status = 'preparing'
     returning to_jsonb(orders.*) into v_row;
  end if;

  if v_row is null then
    update public.dispatch_offers set status = 'expired', responded_at = now() where id::text = p_offer_id;
    return jsonb_build_object('ok', false, 'reason', 'already_taken');
  end if;

  update public.dispatch_offers set status = 'accepted', responded_at = now() where id::text = p_offer_id;

  return jsonb_build_object('ok', true, 'target_type', v_offer.target_type, 'data', v_row);
end;
$function$;
