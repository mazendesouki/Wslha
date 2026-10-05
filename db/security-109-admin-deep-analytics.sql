-- =====================================================================
--  وصّلها — Security #109: تحليلات أعمق للأدمن
--
--  لوحة التحكم الحالية (admin.astro) عندها رسوم بيانية للإيراد/النشاط
--  اليومي آخر 14 يوم بس (محسوبة في المتصفح من بيانات خام، نافذة ثابتة)،
--  وملخص مالي إجمالي (get_platform_finance_summary). لكن مفيش حاجة
--  بتجاوب على: "مين أفضل السائقين؟"، "فين أكتر المناطق طلبًا؟"، "العملاء
--  بيرجعوا يحجزوا تاني ولا لأ؟"، "الدفع كاش ولا محفظة أكتر؟"، أو تدّي
--  اتجاه الإيراد/الحجوزات لفترة مختارة (مش 14 يوم ثابتة بس).
--
--  دالة واحدة (admin_analytics_overview) بترجع JSON فيه كل ده مع بعض
--  لفترة زمنية مختارة (افتراضيًا 30 يوم)، بنفس نمط الحماية بباسورد
--  الأدمن المستخدم في كل دالة admin_* تانية. حقل trend بيرجع نقطة لكل
--  يوم (لو الفترة ≤31 يوم) أو لكل أسبوع (لو أطول) — إيراد + عدد حجوزات
--  (رحلات مكتملة + طلبات مُسلَّمة) محسوبة من السيرفر مباشرة، بديل أدق
--  وأمرن من رسم الـ14-يوم الثابت الموجود بالفعل.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.admin_analytics_overview(
  p_admin_phone text,
  p_admin_password text,
  p_days int default 30
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin record;
  v_cutoff timestamptz;
  v_top_drivers jsonb;
  v_busiest_areas jsonb;
  v_payment_breakdown jsonb;
  v_total_customers int;
  v_repeat_customers int;
  v_unit text;
  v_trend jsonb;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return null; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return null;
  end if;

  v_cutoff := now() - (greatest(coalesce(p_days, 30), 1) || ' days')::interval;

  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_top_drivers from (
    select
      wt.phone,
      coalesce(a.name, '') as name,
      count(*)::int as trips,
      sum(wt.amount) as earnings,
      round(coalesce((
        select avg(r.rating) from public.ratings r
        where r.driver_phone = wt.phone and r.rated_by = 'customer' and r.created_at >= v_cutoff
      ), 0)::numeric, 2) as avg_rating
    from public.wallet_transactions wt
    left join public.accounts a on a.phone = wt.phone
    where wt.type = 'earning' and wt.created_at >= v_cutoff
    group by wt.phone, a.name
    order by sum(wt.amount) desc
    limit 10
  ) t;

  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_busiest_areas from (
    select from_area as area, count(*)::int as ride_count
    from public.rides
    where status = 'completed' and created_at >= v_cutoff and from_area is not null
    group by from_area
    order by count(*) desc
    limit 10
  ) t;

  select coalesce(jsonb_object_agg(payment, jsonb_build_object('count', cnt, 'amount', amt)), '{}'::jsonb) into v_payment_breakdown from (
    select coalesce(payment, 'cash') as payment, count(*)::int as cnt, sum(fare) as amt
    from public.rides
    where status = 'completed' and created_at >= v_cutoff
    group by coalesce(payment, 'cash')
  ) t;

  with cust as (
    select customer_phone from public.rides where status = 'completed' and created_at >= v_cutoff
    union all
    select customer_phone from public.orders where status = 'delivered' and created_at >= v_cutoff
  ),
  counts as (
    select customer_phone, count(*) as c from cust group by customer_phone
  )
  select count(*), count(*) filter (where c > 1) into v_total_customers, v_repeat_customers from counts;

  -- اتجاه الإيراد/الحجوزات — يومي لو الفترة 31 يوم أو أقل، أسبوعي لو
  -- أطول (90 يوم يومي = 90 عمود، كتير على رسم بياني واحد).
  v_unit := case when coalesce(p_days, 30) <= 31 then 'day' else 'week' end;

  with buckets as (
    select generate_series(
      date_trunc(v_unit, v_cutoff),
      date_trunc(v_unit, now()),
      case when v_unit = 'day' then interval '1 day' else interval '1 week' end
    ) as bucket
  ),
  ride_agg as (
    select date_trunc(v_unit, created_at) as bucket, count(*)::int as cnt, sum(fare) as rev
    from public.rides
    where status = 'completed' and created_at >= v_cutoff
    group by 1
  ),
  order_agg as (
    select date_trunc(v_unit, created_at) as bucket, count(*)::int as cnt, sum(total) as rev
    from public.orders
    where status = 'delivered' and created_at >= v_cutoff
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'date', to_char(b.bucket, 'YYYY-MM-DD'),
    'revenue', round(coalesce(r.rev, 0) + coalesce(o.rev, 0), 2),
    'bookings', coalesce(r.cnt, 0) + coalesce(o.cnt, 0)
  ) order by b.bucket), '[]'::jsonb)
  into v_trend
  from buckets b
  left join ride_agg r on r.bucket = b.bucket
  left join order_agg o on o.bucket = b.bucket;

  return jsonb_build_object(
    'days', p_days,
    'top_drivers', v_top_drivers,
    'busiest_areas', v_busiest_areas,
    'payment_breakdown', v_payment_breakdown,
    'total_customers', coalesce(v_total_customers, 0),
    'repeat_customers', coalesce(v_repeat_customers, 0),
    'repeat_customer_rate', case when coalesce(v_total_customers, 0) > 0
      then round(100.0 * v_repeat_customers / v_total_customers, 1)
      else 0 end,
    'trend_unit', v_unit,
    'trend', v_trend
  );
end;
$$;
grant execute on function public.admin_analytics_overview(text, text, int) to anon, authenticated;
