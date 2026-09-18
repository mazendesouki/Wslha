-- =====================================================================
--  وصّلها — Security #71: هدف يومي/أسبوعي للسائق
--
--  عداد تحفيزي بسيط: عدد الرحلات/الطلبات المكتملة اليوم وهذا الأسبوع،
--  محسوب سيرفر-سايد (بدل ما يجيب كل السجل زي driver_orders_screen.dart
--  ويفلتر عميل-سايد — ده استعلام خفيف بالعدد بس).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value) values
  ('driver_daily_goal', '8'),
  ('driver_weekly_goal', '40')
on conflict (key) do nothing;

create or replace function public.get_driver_progress(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_today_start timestamptz := date_trunc('day', now());
  v_week_start timestamptz := date_trunc('week', now());
  v_today int;
  v_week int;
begin
  select
    (select count(*) from public.rides where driver_phone = p_driver_phone and status = 'completed' and completed_at >= v_today_start)
    + (select count(*) from public.orders where driver_phone = p_driver_phone and status = 'delivered' and delivered_at >= v_today_start)
  into v_today;

  select
    (select count(*) from public.rides where driver_phone = p_driver_phone and status = 'completed' and completed_at >= v_week_start)
    + (select count(*) from public.orders where driver_phone = p_driver_phone and status = 'delivered' and delivered_at >= v_week_start)
  into v_week;

  return jsonb_build_object('today', v_today, 'week', v_week);
end;
$$;

grant execute on function public.get_driver_progress(text) to anon, authenticated;
