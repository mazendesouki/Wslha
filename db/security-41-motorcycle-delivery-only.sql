-- =====================================================================
--  وصّلها — Security #41: الدراجة النارية = توصيل فقط (بدون مشاوير/مطار)
--
--  فئة سيارة جديدة "motorcycle" أُضيفت لتسجيل السائقين (driver-apply.astro)
--  مخصّصة لطلبات خدمة الدليفري بس — مش المفروض سائق الدراجة النارية
--  يستقبل أو يقبل أي عرض "رحلة" (مشوار محلي/خارجي/مطار) أبدًا.
--
--  نفس نمط استبعاد الرحلات التفاوضية في security-36 (فلترة عند القراءة،
--  مش عند إنشاء العرض في محرك الديسباتش الخارجي server/index.js — ده
--  إصلاح فوري يشتغل من غير إعادة نشر الخادم):
--   1) get_my_pending_offer / get_my_pending_offers: بتستبعد أي عرض
--      target_type='ride' لو فئة السائق motorcycle (عروض الدليفري
--      target_type='order' تفضل تظهر عادي).
--   2) accept_dispatch_offer: فحص دفاعي إضافي — لو عرض رحلة وصل فعلاً
--      لسائق دراجة نارية (مثلاً قبل تفعيل هذا الأمان)، يترفض برسالة
--      واضحة بدل ما يتقبل.
--   3) submit_ride_price_offer: يمنع سائق الدراجة النارية من تقديم عرض
--      سعر على رحلة تفاوضية (نفس المبدأ — دي "رحلة" برضو).
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- ── 1) get_my_pending_offer (مفرد) ──
create or replace function public.get_my_pending_offer(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer public.dispatch_offers;
  v_data  jsonb;
  v_ride_negotiable boolean;
  v_driver_cat text;
begin
  select * into v_offer
  from public.dispatch_offers
  where driver_phone = p_driver_phone
    and status = 'pending'
    and expires_at > now()
  order by offered_at desc
  limit 1;

  if not found then return null; end if;

  if v_offer.target_type = 'ride' then
    select vehicle_category into v_driver_cat
    from public.driver_applications
    where phone::text = p_driver_phone
    order by created_at desc
    limit 1;
    if v_driver_cat = 'motorcycle' then return null; end if;

    select to_jsonb(r), coalesce(r.is_negotiable, false) into v_data, v_ride_negotiable
    from public.rides r where r.id::text = v_offer.target_id;
    if v_ride_negotiable then return null; end if;
  else
    select to_jsonb(o) into v_data from public.orders o where o.id::text = v_offer.target_id;
  end if;

  if v_data is null then return null; end if;

  return jsonb_build_object(
    'offer_id',    v_offer.id,
    'target_type', v_offer.target_type,
    'expires_at',  v_offer.expires_at,
    'data',        v_data
  );
end;
$$;

revoke all on function public.get_my_pending_offer(text) from public;
grant execute on function public.get_my_pending_offer(text) to anon, authenticated;

-- ── 2) get_my_pending_offers (جمع) ──
create or replace function public.get_my_pending_offers(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_driver_cat text;
begin
  select vehicle_category into v_driver_cat
  from public.driver_applications
  where phone::text = p_driver_phone
  order by created_at desc
  limit 1;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'offer_id', d.id,
        'target_type', d.target_type,
        'expires_at', d.expires_at,
        'data', case when d.target_type = 'ride' then to_jsonb(r) else to_jsonb(ord) end
      )
      order by d.offered_at desc
    ),
    '[]'::jsonb
  ) into v_result
  from public.dispatch_offers d
  left join public.rides  r   on d.target_type = 'ride'  and r.id::text = d.target_id
  left join public.orders ord on d.target_type = 'order' and ord.id::text = d.target_id
  where d.driver_phone = p_driver_phone
    and d.status = 'pending'
    and d.expires_at > now()
    and ((d.target_type = 'ride' and r.id is not null and coalesce(r.is_negotiable, false) = false
          and v_driver_cat is distinct from 'motorcycle')
         or (d.target_type = 'order' and ord.id is not null));

  return v_result;
end;
$$;

revoke all on function public.get_my_pending_offers(text) from public;
grant execute on function public.get_my_pending_offers(text) to anon, authenticated;

-- ── 3) accept_dispatch_offer — فحص دفاعي إضافي ──
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
  v_driver_status  text;
begin
  select * into v_offer
  from public.dispatch_offers
  where id::text = p_offer_id and driver_phone::text = p_driver_phone
  for update;

  if not found or v_offer.status <> 'pending' or v_offer.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'expired_or_taken');
  end if;

  select status into v_driver_status
  from public.driver_applications
  where phone::text = p_driver_phone
  order by created_at desc
  limit 1;

  if v_driver_status is distinct from 'approved' then
    update public.dispatch_offers set status = 'rejected', responded_at = now() where id::text = p_offer_id;
    return jsonb_build_object('ok', false, 'reason', 'driver_not_approved');
  end if;

  if v_offer.target_type = 'ride' then
    select vehicle_category into v_driver_cat
    from public.driver_applications
    where phone::text = p_driver_phone
    order by created_at desc
    limit 1;

    if v_driver_cat = 'motorcycle' then
      update public.dispatch_offers set status = 'rejected', responded_at = now() where id::text = p_offer_id;
      return jsonb_build_object('ok', false, 'reason', 'motorcycle_delivery_only');
    end if;

    select airport_vehicle_category, airport_quality_tier
      into v_required_cat, v_required_tier
    from public.rides
    where id::text = v_offer.target_id and ride_type = 'airport';

    if v_required_cat is not null or v_required_tier is not null then
      select has_ac, is_clean, vehicle_year
        into v_driver_has_ac, v_driver_is_clean, v_driver_year
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

-- ── 4) submit_ride_price_offer — منع سائق الدراجة النارية من التفاوض على رحلة ──
create or replace function public.submit_ride_price_offer(
  p_ride_id uuid, p_driver_phone text, p_driver_name text, p_price numeric
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_ride record; v_row record; v_driver_cat text;
begin
  if p_price is null or p_price <= 0 then
    raise exception 'invalid_price';
  end if;

  select vehicle_category into v_driver_cat
  from public.driver_applications
  where phone::text = p_driver_phone
  order by created_at desc
  limit 1;
  if v_driver_cat = 'motorcycle' then
    raise exception 'motorcycle_delivery_only';
  end if;

  select * into v_ride from public.rides where id = p_ride_id;
  if v_ride.id is null then raise exception 'ride_not_found'; end if;
  if not coalesce(v_ride.is_negotiable, false) then raise exception 'not_negotiable'; end if;
  if v_ride.status <> 'pending' or v_ride.driver_phone is not null then
    raise exception 'ride_already_taken';
  end if;

  insert into public.ride_price_offers (ride_id, driver_phone, driver_name, offered_price)
  values (p_ride_id, p_driver_phone, p_driver_name, p_price)
  on conflict (ride_id, driver_phone)
  do update set offered_price = excluded.offered_price,
                driver_name   = excluded.driver_name,
                status        = 'pending',
                created_at    = now()
  returning to_jsonb(ride_price_offers.*) into v_row;

  return to_jsonb(v_row);
end;
$$;
grant execute on function public.submit_ride_price_offer(uuid, text, text, numeric) to anon, authenticated;
