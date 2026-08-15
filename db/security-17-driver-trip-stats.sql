-- =====================================================================
--  وصّلها — Security #17: إحصائيات الرحلات للسائق (Driver trip analytics)
--
--  المطلوب: داشبورد للسائق يوريه رحلاته الداخلية vs الخارجية، وتوزيع
--  الرحلات الخارجية والمطار على المحافظات، وطريقة الدفع (كاش/تحويل/محفظة)،
--  والأرباح الحقيقية بعد العمولة.
--
--  rides مفيهاش عمود "محافظة" أصلاً — الرحلات الخارجية كانت بتتسجل
--  بعنوان نصي حر من غير ما نعرف تبع أنهي محافظة. الحل: نضيف عمود
--  governorate (يتملى وقت الحجز — دمياط الجديدة تلقائيًا للرحلات
--  المحلية، من اختيار العميل للرحلات الخارجية، ومن محافظة المطار
--  تلقائيًا لرحلات المطار)، وعمود airport_id اختياري لربط رحلة المطار
--  بمطار محدد بدل مطابقة النص.
--
--  الأرباح بتتحسب من wallet_transactions (type='earning', reference_id
--  = ride id) بدل ما نعيد حساب fare×rate تاني على العميل — نفس مصدر
--  الحقيقة اللي settle_ride_commission بيكتبه (security-07).
--
--  Run this whole file once in the Supabase SQL Editor. Idempotent.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 0) Columns
-- ---------------------------------------------------------------------
alter table public.rides add column if not exists governorate text;
alter table public.rides add column if not exists airport_id  text;

-- ---------------------------------------------------------------------
-- 1) get_driver_trip_stats — كل الإحصائيات محسوبة على السيرفر، مبنية
--    على رحلات السائق نفسه بس (نفس منطق ownership اللي settle_ride_
--    commission بيستخدمه — بدون كلمة مرور، رقم الجوال هو نفس آلية
--    الهوية المستخدمة في كل استعلامات السائق الأخرى في التطبيق).
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
  overall as (
    select count(*) as trips, coalesce(sum(fare),0) as fare_total, coalesce(sum(driver_earn),0) as earnings_total
    from my_rides
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
    'by_type',         coalesce((select jsonb_agg(row_to_json(by_type))     from by_type), '[]'::jsonb),
    'by_governorate',  coalesce((select jsonb_agg(row_to_json(by_gov))      from by_gov), '[]'::jsonb),
    'by_airport',      coalesce((select jsonb_agg(row_to_json(by_airport))  from by_airport), '[]'::jsonb),
    'by_payment',      coalesce((select jsonb_agg(row_to_json(by_payment))  from by_payment), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.get_driver_trip_stats(text) to anon, authenticated;
