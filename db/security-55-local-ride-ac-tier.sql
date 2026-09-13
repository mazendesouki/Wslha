-- =====================================================================
--  وصّلها — Security #55: اختيار "عربية مكيّفة/عادية" للمشاوير العادية
--  (مش بس رحلات المطار)
--
--  الطلب: العميل يقدر يختار عربية مكيّفة أو عادية للمشوار العادي/الخارجي
--  (زي رحلات المطار بالظبط)، والسعر يختلف حسب الاختيار، ولازم السائق
--  اللي هيقبل الرحلة تكون عربيته مطابقة فعلاً لاختيار العميل (مكيّفة لو
--  طلب مكيّفة).
--
--  الحل بيعيد استخدام نفس العمود والمنطق الموجودين بالفعل لرحلات المطار
--  (airport_quality_tier + accept_dispatch_offer من security-10) —
--  بدل عمود جديد، وبدل نظام تحقق تاني:
--
--   1) guard_ride_fare() (السعر النهائي الحقيقي اللي بيتحصّل): كان
--      بيتجاهل airport_quality_tier تمامًا للمشاوير العادية/الخارجية —
--      دلوقتي بيضرب السعر في نفس معامل الزيادة المستخدم لرحلات المطار
--      (مكيّفة = ×1.12، زي qualityMultiplier في
--      flutter_app/lib/features/airport/airport_fare.dart).
--
--   2) accept_dispatch_offer() (security-10): كان بيتحقق من
--      airport_quality_tier بس لو ride_type = 'airport'. الشرط ده
--      اتشال — النهاردة بيتحقق من أي رحلة عندها قيمة في العمود ده، أيًا
--      كان نوعها. فحص airport_vehicle_category فضل زي ما هو (بيفضل
--      يرجع NULL دايمًا للمشاوير العادية، فمفيش تأثير عليها).
--
--  ملاحظة: زي القيود الموجودة بالفعل على رحلات المطار — التحقق ده بيحصل
--  وقت القبول بس (مش وقت اختيار السائقين المرشحين في محرك التوزيع
--  server/index.js)، فسائق من غير تكييف لسه ممكن يستقبل العرض، بس
--  قبوله هيترفض برسالة quality_tier_mismatch. نفس القيد الموجود من زمان
--  لرحلات المطار، مش قيد جديد.
--
--  لازم تحدّث الكود بعد تشغيل الملف ده (flutter ride_repository.dart +
--  fare_calculator.dart + rides_screen.dart) — موجود في نفس الكوميت.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) guard_ride_fare — يضرب السعر في معامل الفئة (مكيّفة/عادية) لأي
--    رحلة عادية أو خارجية عندها airport_quality_tier محدد.
-- ---------------------------------------------------------------------
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
  v_tier_mult     numeric;
begin
  select category into v_category from public.vehicle_rates where id = new.vehicle_model;
  if v_category is null then
    v_category := 'sedan';
  end if;

  v_mult := least(1.35, greatest(0.8, 1 + (coalesce(new.vehicle_year, 2022) - 2021) * 0.035));

  -- نفس القيم بالظبط المستخدمة في airport_fare.dart's qualityMultiplier —
  -- لازم يفضلوا متطابقين، أي تغيير هنا لازم يتغيّر هناك كمان.
  v_tier_mult := case coalesce(new.airport_quality_tier, 'regular')
    when 'ac'     then 1.12
    when 'clean'  then 1.08
    when 'modern' then 1.20
    else 1.0
  end;

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

    v_raw := ((25 + v_tiered * v_effrate) * coalesce(v_zone.factor, 1) + coalesce(v_zone.surcharge, 0)) * v_tier_mult;
    new.fare := ceil(greatest(v_raw, 40) / 5) * 5;

  elsif new.ride_type = 'external' then
    v_effrate := v_rate_external * v_mult;
    v_km := coalesce(new.distance_km, 0);
    v_raw := (50 + v_km * v_effrate) * v_tier_mult;
    new.fare := ceil(greatest(v_raw, 150) / 5) * 5;
  end if;
  -- ride_type='airport': يُحسب في الواجهة — بلا إعادة حساب هنا حالياً.
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 2) accept_dispatch_offer — فحص airport_quality_tier بقى لأي رحلة، مش
--    بس ride_type='airport'.
-- ---------------------------------------------------------------------
create or replace function public.accept_dispatch_offer(
  p_offer_id    text,
  p_driver_phone text,
  p_driver_name  text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer public.dispatch_offers;
  v_row   jsonb;
  v_required_cat   text;
  v_required_tier  text;
  v_driver_cat     text;
  v_driver_has_ac  boolean;
  v_driver_is_clean boolean;
  v_driver_year    int;
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
    -- كان فيه شرط "and ride_type = 'airport'" هنا — اتشال عشان الفحص
    -- يشتغل لأي نوع رحلة. airport_vehicle_category بيفضل NULL دايمًا
    -- للمشاوير العادية (محدش بيحطها غير رحلات المطار)، فمفيش تأثير على
    -- فحص الفئة القديم.
    select airport_vehicle_category, airport_quality_tier
      into v_required_cat, v_required_tier
    from public.rides
    where id::text = v_offer.target_id;

    if v_required_cat is not null or v_required_tier is not null then
      select vehicle_category, has_ac, is_clean, vehicle_year
        into v_driver_cat, v_driver_has_ac, v_driver_is_clean, v_driver_year
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
          when 'modern'  then coalesce(v_driver_year, 0) >= (extract(year from now())::int - 3)
          when 'regular' then not coalesce(v_driver_has_ac, false) and not coalesce(v_driver_is_clean, false)
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
$$;

revoke all on function public.accept_dispatch_offer(text, text, text) from public;
grant execute on function public.accept_dispatch_offer(text, text, text) to anon, authenticated;
