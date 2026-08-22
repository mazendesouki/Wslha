-- =====================================================================
--  وصّلها — Security #33: إصلاح إجمالي رحلات السائق + عمود tags الناقص
--
--  اكتشفنا السبب الحقيقي وراء ظهور "إجمالي رحلاتي" = 0 وسجل التقييمات
--  فاضي في تطبيق السائق عن طريق بانر تشخيصي مؤقت أظهر رسالتين خطأ حقيقيتين:
--
--  1) get_driver_trip_stats() (من security-28) كانت بتقارن
--     wallet_transactions.reference_id (نوعه text) مباشرة مع rides.id
--     (نوعه uuid) من غير تحويل نوع — "operator does not exist: text =
--     uuid". نفس الجوين بتاع orders كان معمول صح (::text) بس rides لأ.
--     النتيجة: أي استعلام لإحصائيات السائق كان بيفشل بالكامل ويرجع صفر
--     في كل حاجة، مش بس أرباح الرحلات.
--
--  2) عمود ratings.tags (المفروض يتضاف في security-24-ratings-plus.sql)
--     مش موجود فعليًا على قاعدة البيانات دي — يعني الملف ده ما اتشغلش
--     قبل كده. driverReviews() في تطبيق السائق بتحاول تقرأ العمود ده
--     فيفشل الاستعلام كله ويرجع قائمة فاضية، رغم إن متوسط التقييم نفسه
--     (اللي مش محتاج عمود tags) كان شغال صح.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) عمود tags (نفس security-24 — لو كان اتشغل قبل كده، الأمر ده مايعملش حاجة)
-- ---------------------------------------------------------------------
alter table public.ratings add column if not exists tags text[];

create index if not exists ratings_driver_rated_by_idx on public.ratings (driver_phone, rated_by);
create index if not exists ratings_customer_rated_by_idx on public.ratings (customer_phone, rated_by);
create index if not exists ratings_store_idx on public.ratings (store_id);
create index if not exists ratings_order_code_idx on public.ratings (order_code);

-- ---------------------------------------------------------------------
-- 2) get_driver_trip_stats — تصحيح مقارنة النوع لـ my_rides (r.id::text)
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
    ) w on w.reference_id = r.id::text
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
