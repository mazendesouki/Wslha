-- =====================================================================
--  وصّلها — إضافة بيانات بروفايل السائق: صورة شخصية + إحصائية طلبات المتاجر
--
--  1) عمود avatar_url على accounts (صورة شخصية يرفعها المستخدم بنفسه من
--     الملف الشخصي — مختلف عن driver_applications.driver_photo_url اللي
--     هو صورة التقديم/التوثيق وقت التسجيل فقط).
--  2) lookup_account يرجّع avatar_url كمان.
--  3) توسيع get_driver_trip_stats (security-17) بفئة "store_orders" —
--     كانت بتغطي rides بس (محلي/خارجي/مطار)، وده بيضيف طلبات التوصيل من
--     المتاجر (orders.status='delivered') بنفس منطق الأرباح
--     (wallet_transactions type='earning').
--
--  آمن لإعادة التشغيل. شغّله كامل مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) avatar_url
-- ---------------------------------------------------------------------
alter table public.accounts add column if not exists avatar_url text;

-- ---------------------------------------------------------------------
-- 2) lookup_account — يرجّع avatar_url كمان
-- ---------------------------------------------------------------------
create or replace function public.lookup_account(p_phone text)
returns table(
  id uuid, phone text, name text, role text, city text,
  email text, username text, status text, created_at timestamptz,
  avatar_url text
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select a.id, a.phone, a.name, a.role, a.city, a.email, a.username, a.status, a.created_at, a.avatar_url
  from public.accounts a
  where a.phone in (
    p_phone,
    case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end,
    case when p_phone like '0%'   then '+2'||p_phone           else p_phone end
  )
  limit 1;
$$;
grant execute on function public.lookup_account(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) get_driver_trip_stats — إضافة store_orders لنفس الـ JSON الناتج
-- ---------------------------------------------------------------------
create or replace function public.get_driver_trip_stats(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_local  text;
  v_intl   text;
  v_result jsonb;
begin
  if p_driver_phone is null or length(trim(p_driver_phone)) = 0 then
    raise exception 'driver_phone_required';
  end if;

  v_local := case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end;
  v_intl  := case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end;

  with my_rides as (
    select r.*,
           coalesce(w.earn, 0) as driver_earn
    from public.rides r
    left join (
      select reference_id, sum(amount) as earn
      from public.wallet_transactions
      where type = 'earning'
      group by reference_id
    ) w on w.reference_id = r.id
    where r.driver_phone in (v_local, v_intl)
      and r.status = 'completed'
  ),
  my_orders as (
    select o.*,
           coalesce(w.earn, 0) as driver_earn
    from public.orders o
    left join (
      select reference_id, sum(amount) as earn
      from public.wallet_transactions
      where type = 'earning'
      group by reference_id
    ) w on w.reference_id = o.id::text
    where o.driver_phone in (v_local, v_intl)
      and o.status = 'delivered'
  ),
  overall as (
    select count(*) as trips, coalesce(sum(fare),0) as fare_total, coalesce(sum(driver_earn),0) as earnings_total
    from my_rides
  ),
  store_orders as (
    select count(*) as trips, coalesce(sum(delivery_fee),0) as fare_total, coalesce(sum(driver_earn),0) as earnings_total
    from my_orders
  ),
  by_type as (
    select coalesce(ride_type,'local') as ride_type,
           count(*) as trips, coalesce(sum(fare),0) as fare_total, coalesce(sum(driver_earn),0) as earnings_total
    from my_rides
    group by coalesce(ride_type,'local')
  ),
  by_gov as (
    select coalesce(nullif(trim(governorate),''), 'غير محدد') as governorate,
           count(*) as trips, coalesce(sum(fare),0) as fare_total, coalesce(sum(driver_earn),0) as earnings_total
    from my_rides
    where ride_type in ('local','external')
    group by 1
    order by earnings_total desc
  ),
  by_airport as (
    select coalesce(
             nullif(trim(airport_id),''),
             case when to_area   like '%مطار%' then to_area
                  when from_area like '%مطار%' then from_area
                  else coalesce(to_area, from_area, 'غير محدد') end
           ) as airport,
           count(*) as trips, coalesce(sum(fare),0) as fare_total, coalesce(sum(driver_earn),0) as earnings_total
    from my_rides
    where ride_type = 'airport'
    group by 1
    order by earnings_total desc
  ),
  by_payment as (
    select coalesce(nullif(trim(payment),''), 'cash') as payment,
           count(*) as trips, coalesce(sum(fare),0) as fare_total, coalesce(sum(driver_earn),0) as earnings_total
    from my_rides
    group by 1
    order by trips desc
  )
  select jsonb_build_object(
    'overall',        (select row_to_json(overall) from overall),
    'store_orders',   (select row_to_json(store_orders) from store_orders),
    'by_type',         coalesce((select jsonb_agg(row_to_json(by_type))     from by_type), '[]'::jsonb),
    'by_governorate',  coalesce((select jsonb_agg(row_to_json(by_gov))      from by_gov), '[]'::jsonb),
    'by_airport',      coalesce((select jsonb_agg(row_to_json(by_airport))  from by_airport), '[]'::jsonb),
    'by_payment',      coalesce((select jsonb_agg(row_to_json(by_payment))  from by_payment), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.get_driver_trip_stats(text) to anon, authenticated;
