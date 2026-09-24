-- =====================================================================
--  وصّلها — Security #93: قبول/رفض طلب فايت من سجل الرحلات
--
--  الطلب: سجل الرحلات (security-92) كان للعرض بس. المطلوب دلوقتي: السائق
--  يقدر "يسترجع" طلب فاته (اتقفل صلاحيته وهو أوفلاين) لو لسه متاح فعليًا
--  (محدش قبله)، من غير عدّاد 30 ثانية — قرار غير مستعجل، مش عرض حي.
--  ومسموح حتى لو السائق حاليًا مسجّل "غير متصل"، لأن ده استرجاع يدوي
--  مش توزيع تلقائي.
--
--  الفرق عن accept_dispatch_offer العادية: مبتشترطش status='pending' أو
--  expires_at لسه سارية — بس بتتأكد (زي الأصلية بالظبط) إن الرحلة/الطلب
--  لسه من غير سائق فعليًا قبل ما تسنده، فمفيش خطر إنه ياخد حاجة
--  السائق التاني قبلها فعلاً.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- تتبّع "إخفاء" طلب من السجل (زرار رفض) من غير ما يأثر على أي منطق ديسباتش
-- تاني بيقرا الجدول ده.
alter table public.dispatch_offers add column if not exists driver_dismissed_at timestamptz;

-- get_driver_missed_requests (security-92) بتترجع كمان still_available —
-- علشان تطبيق السائق يعرف يعرض زرار "قبول" بس لو الرحلة/الطلب لسه فعلاً
-- من غير سائق، ويخفي الرحلة اللي اتشالت (driver_dismissed_at).
create or replace function public.get_driver_missed_requests(p_driver_phone text)
returns table(
  id text, target_type text, offered_at timestamptz, expires_at timestamptz,
  from_area text, to_area text, fare numeric, distance_km numeric,
  customer_name text, store_name text, order_total numeric, still_available boolean
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    o.id, o.target_type, o.offered_at, o.expires_at,
    r.from_area, r.to_area, r.fare, r.distance_km, r.customer_name,
    s.name as store_name, ord.total as order_total,
    case
      when o.target_type = 'ride'  then (r.driver_phone is null and r.status = 'pending')
      when o.target_type = 'order' then (ord.driver_phone is null and ord.status = 'preparing')
      else false
    end as still_available
  from public.dispatch_offers o
  left join public.rides  r   on o.target_type = 'ride'  and r.id::text = o.target_id
  left join public.orders ord on o.target_type = 'order' and ord.id::text = o.target_id
  where o.driver_phone = p_driver_phone
    and o.status = 'expired'
    and o.driver_dismissed_at is null
    and o.offered_at > now() - interval '30 days'
  order by o.offered_at desc
  limit 100;
$$;
grant execute on function public.get_driver_missed_requests(text) to anon, authenticated;

-- قبول طلب فايت — نفس منطق الأهلية (فئة العربية/مستوى الخدمة) وشرط
-- "لسه من غير سائق" بتاع accept_dispatch_offer بالظبط، بدون شرط
-- pending/expires_at.
create or replace function public.accept_missed_request(
  p_offer_id text, p_driver_phone text, p_driver_name text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_offer public.dispatch_offers;
  v_row   jsonb;
  v_required_cat   text;
  v_required_tier  text;
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

  if not found or v_offer.status <> 'expired' then
    return jsonb_build_object('ok', false, 'reason', 'not_a_missed_request');
  end if;

  if v_offer.target_type = 'ride' then
    select airport_vehicle_category, airport_quality_tier
      into v_required_cat, v_required_tier
    from public.rides
    where id::text = v_offer.target_id;

    if v_required_cat is not null or v_required_tier is not null then
      select vehicle_category, has_ac, is_clean, is_modern
        into v_driver_cat, v_driver_has_ac, v_driver_is_clean, v_driver_is_modern
      from public.driver_applications
      where phone::text = p_driver_phone and status = 'approved'
      order by created_at desc
      limit 1;

      if v_required_cat is not null and v_driver_cat is distinct from v_required_cat then
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
          return jsonb_build_object('ok', false, 'reason', 'quality_tier_mismatch');
        end if;
      end if;
    end if;

    update public.rides
       set status = 'accepted', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), accepted_at = now()
     where id::text = v_offer.target_id and driver_phone is null and status = 'pending'
     returning to_jsonb(rides.*) into v_row;
  else
    update public.orders
       set status = 'on_the_way', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), picked_up_at = null
     where id::text = v_offer.target_id and driver_phone is null and status = 'preparing'
     returning to_jsonb(orders.*) into v_row;
  end if;

  if v_row is null then
    -- حد تاني قبلها فعلاً — نخفيها من السجل عشان متبقاش تظهر كإنها
    -- لسه متاحة.
    update public.dispatch_offers set driver_dismissed_at = now() where id::text = p_offer_id;
    return jsonb_build_object('ok', false, 'reason', 'already_taken');
  end if;

  update public.dispatch_offers set driver_dismissed_at = now() where id::text = p_offer_id;

  return jsonb_build_object('ok', true, 'target_type', v_offer.target_type, 'data', v_row);
end;
$$;
grant execute on function public.accept_missed_request(text, text, text) to anon, authenticated;

-- إخفاء طلب فايت من السجل (زرار "رفض") — من غير أي أثر على الرحلة/الطلب
-- نفسه، لأنه أصلاً مش متسند للسائق ده.
create or replace function public.dismiss_missed_request(p_offer_id text, p_driver_phone text)
returns boolean
language sql
security definer
set search_path = public, extensions
as $$
  update public.dispatch_offers
     set driver_dismissed_at = now()
   where id::text = p_offer_id and driver_phone::text = p_driver_phone
  returning true;
$$;
grant execute on function public.dismiss_missed_request(text, text) to anon, authenticated;
