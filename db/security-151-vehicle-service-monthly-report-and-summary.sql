-- =====================================================================
--  وصّلها — Security #151: تقرير شهري + ملخص شامل لسجل خدمة وصيانة
--  المركبة
--
--  3 دوال جديدة بتخدم "سجل خدمة وصيانة المركبة" الموسّع:
--
--  1) get_my_vehicle_service_monthly_report: كل السجلات بتاعة شهر
--     وسنة معيّنين (للعرض التفصيلي).
--  2) get_my_vehicle_service_monthly_totals: إجمالي التكلفة وعدد
--     العمليات لكل نوع خدمة خلال نفس الشهر — الواجهة تجمعهم للإجمالي
--     الكلي.
--  3) get_my_vehicle_service_summary: ملخص شامل (مش مقيّد بشهر) —
--     لكل "اسم خدمة" (عنصر صيانة دورية بعينه، أو نوع خدمة زي وقود/
--     كاوتش/زيت/فحص، أو خدمة تانية بعنوانها المخصّص): عدد مرات التنفيذ،
--     إجمالي التكلفة، وتاريخ آخر تنفيذ. بيرجع item_key/service_type/
--     custom_label خام (من غير تسمية جاهزة) — نفس أسلوب باقي الكود،
--     التسمية بتتحسب في Flutter من الخرائط الموجودة فعلاً
--     (_serviceTypeLabels/_maintenanceItemLabels).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.get_my_vehicle_service_monthly_report(
  p_driver_phone text, p_year int, p_month int
)
returns setof public.vehicle_service_logs
language sql
stable
security definer
set search_path = public, extensions
as $$
  select * from public.vehicle_service_logs
   where driver_phone in (
       p_driver_phone,
       case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
       case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end
     )
     and extract(year from performed_at) = p_year
     and extract(month from performed_at) = p_month
   order by performed_at desc;
$$;
grant execute on function public.get_my_vehicle_service_monthly_report(text, int, int) to anon, authenticated;

create or replace function public.get_my_vehicle_service_monthly_totals(
  p_driver_phone text, p_year int, p_month int
)
returns table(service_type text, entries_count bigint, total_cost numeric)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select service_type, count(*) as entries_count, sum(coalesce(cost, 0)) as total_cost
    from public.vehicle_service_logs
   where driver_phone in (
       p_driver_phone,
       case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
       case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end
     )
     and extract(year from performed_at) = p_year
     and extract(month from performed_at) = p_month
   group by service_type
   order by total_cost desc;
$$;
grant execute on function public.get_my_vehicle_service_monthly_totals(text, int, int) to anon, authenticated;

create or replace function public.get_my_vehicle_service_summary(p_driver_phone text)
returns table(
  service_type text, maintenance_item_key text, custom_label text,
  entries_count bigint, total_cost numeric, last_performed_at timestamptz
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with canon as (
    select
      service_type,
      case when service_type = 'maintenance' and maintenance_items is not null and array_length(maintenance_items, 1) = 1
           then maintenance_items[1] else null end as maintenance_item_key,
      case when service_type = 'other' then custom_label else null end as custom_label,
      cost, performed_at
      from public.vehicle_service_logs
     where driver_phone in (
         p_driver_phone,
         case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
         case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end
       )
  )
  select service_type, maintenance_item_key, custom_label,
         count(*) as entries_count, sum(coalesce(cost, 0)) as total_cost, max(performed_at) as last_performed_at
    from canon
   group by service_type, maintenance_item_key, custom_label
   order by last_performed_at desc;
$$;
grant execute on function public.get_my_vehicle_service_summary(text) to anon, authenticated;
