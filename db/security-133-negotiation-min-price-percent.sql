-- =====================================================================
--  وصّلها — Security #133: نسبة الحد الأدنى للتفاوض — قابلة للتحكم من
--  لوحة الإدارة
--
--  security-132 فرض إن عرض السائق على رحلة تفاوضية ميكونش أقل من
--  rides.fare (السعر العادل) — ثابت 100% بالظبط. الأدمن محتاج يتحكم
--  في النسبة دي بنفسه من اللوحة (مثلاً يسمح بـ 90% في وقت الركود، أو
--  يرفعها لـ 110% وقت الذروة) بدل ما تكون مكتوبة في الكود.
--
--  إضافة setting جديد 'negotiation_min_price_pct' (افتراضي 100 =
--  نفس السلوك الحالي بالظبط)، وتحديث submit_ride_price_offer/
--  accept_ride_price_offer عشان يحسبوا الحد الأدنى = fare × النسبة
--  دي بدل fare نفسه مباشرة.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value) values
  ('negotiation_min_price_pct', '100')
on conflict (key) do nothing;

create or replace function public.submit_ride_price_offer(p_ride_id uuid, p_driver_phone text, p_driver_name text, p_price numeric)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_ride record; v_row record; v_driver_cat text; v_floor numeric;
begin
  if p_price is null or p_price <= 0 then
    raise exception 'invalid_price';
  end if;

  select vehicle_category into v_driver_cat
  from public.driver_applications
  where phone::text = p_driver_phone
  order by created_at desc
  limit 1;
  if v_driver_cat in ('motorcycle', 'cargo', 'box_truck', 'flatbed') then
    raise exception 'delivery_only_vehicle';
  end if;

  select * into v_ride from public.rides where id = p_ride_id;
  if v_ride.id is null then raise exception 'ride_not_found'; end if;
  if not coalesce(v_ride.is_negotiable, false) then raise exception 'not_negotiable'; end if;
  if v_ride.status <> 'pending' or v_ride.driver_phone is not null then
    raise exception 'ride_already_taken';
  end if;

  v_floor := v_ride.fare * public._pricing_setting_num('negotiation_min_price_pct', 100, 1, 500) / 100;
  if p_price < v_floor then
    raise exception 'price_below_fair_fare:%', round(v_floor, 2);
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

create or replace function public.accept_ride_price_offer(p_ride_id uuid, p_offer_id uuid, p_customer_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_ride record; v_offer record; v_updated record; v_floor numeric;
begin
  select * into v_ride from public.rides where id = p_ride_id;
  if v_ride.id is null then raise exception 'ride_not_found'; end if;

  if v_ride.customer_phone not in (
       p_customer_phone,
       case when p_customer_phone like '+20%' then '0'||substr(p_customer_phone,4) else p_customer_phone end,
       case when p_customer_phone like '0%'   then '+2'||p_customer_phone           else p_customer_phone end
     ) then
    raise exception 'not_your_ride';
  end if;

  select * into v_offer from public.ride_price_offers where id = p_offer_id and ride_id = p_ride_id;
  if v_offer.id is null then raise exception 'offer_not_found'; end if;
  if v_offer.status <> 'pending' then raise exception 'offer_no_longer_available'; end if;

  v_floor := v_ride.fare * public._pricing_setting_num('negotiation_min_price_pct', 100, 1, 500) / 100;
  if v_offer.offered_price < v_floor then
    raise exception 'price_below_fair_fare:%', round(v_floor, 2);
  end if;

  update public.rides
     set status = 'accepted',
         driver_phone = v_offer.driver_phone,
         driver_name  = coalesce(v_offer.driver_name, driver_name),
         fare = v_offer.offered_price,
         accepted_at = now()
   where id = p_ride_id and driver_phone is null
   returning to_jsonb(rides.*) into v_updated;

  if v_updated is null then
    raise exception 'ride_already_taken';
  end if;

  update public.ride_price_offers set status = 'accepted' where id = p_offer_id;
  update public.ride_price_offers set status = 'rejected'
   where ride_id = p_ride_id and id <> p_offer_id and status = 'pending';

  return to_jsonb(v_updated);
end;
$$;
