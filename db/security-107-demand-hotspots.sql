-- =====================================================================
--  وصّلها — Security #107: خريطة "مناطق الطلب الساخنة" للسائق
--
--  السائق مكانش عنده أي طريقة يعرف بيها فين الطلب كتير دلوقتي غير إنه
--  يستنى يتصل ويشوف. الحل: دالة قراءة بسيطة (مفيش بيانات حساسة —
--  إحداثيات مجمّعة بس، زي get_available_drivers_count_by_category
--  الموجودة بالفعل) بترجع "خلايا" جغرافية (تقريب الإحداثيات لخانتين
--  عشري ≈ 1.1 كم) فيها رحلات/طلبات لسه مفيهاش سائق، في آخر نافذة زمنية،
--  مرتبة من الأعلى طلبًا للأقل.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.get_demand_hotspots(p_window_minutes int default 45)
returns table(lat double precision, lng double precision, ride_count bigint, order_count bigint, demand_count bigint)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with pending_rides as (
    select round(from_lat::numeric, 2)::float8 as glat, round(from_lng::numeric, 2)::float8 as glng
    from public.rides
    where status = 'pending' and driver_phone is null
      and from_lat is not null and from_lng is not null
      and created_at >= now() - (greatest(coalesce(p_window_minutes, 45), 5) || ' minutes')::interval
  ),
  pending_orders as (
    select round(store_lat::numeric, 2)::float8 as glat, round(store_lng::numeric, 2)::float8 as glng
    from public.orders
    where status = 'preparing' and driver_phone is null
      and store_lat is not null and store_lng is not null
      and created_at >= now() - (greatest(coalesce(p_window_minutes, 45), 5) || ' minutes')::interval
  ),
  combined as (
    select glat, glng, 1 as is_ride, 0 as is_order from pending_rides
    union all
    select glat, glng, 0, 1 from pending_orders
  )
  select glat as lat, glng as lng,
         sum(is_ride)::bigint as ride_count,
         sum(is_order)::bigint as order_count,
         count(*)::bigint as demand_count
  from combined
  group by glat, glng
  order by demand_count desc
  limit 30;
$$;
grant execute on function public.get_demand_hotspots(int) to anon, authenticated;
