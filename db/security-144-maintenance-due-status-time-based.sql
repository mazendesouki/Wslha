-- =====================================================================
--  وصّلها — Security #144: حساب الصيانة الدورية بالوقت كمان، مش بالكيلومتر بس
--
--  maintenance_catalog_items (security-142) فيه interval_months لعناصر
--  زمنها بيبوّظ مع الوقت بردو (مثال: زيت/سائل الفرامل، البطارية، سائل
--  التبريد — كل واحد منهم عنده interval_km *و* interval_months)، لكن
--  get_maintenance_due_status كانت بتتجاهل الشق الزمني بالكامل وبتحسب
--  على الكيلومتر لوحده. سائق بيمشي كيلومترات قليلة لكن فات على آخر
--  تغيير سنتين، مثلاً، كان العنصر يفضل 'ok' غلط لمجرد إنه لسه ما وصلش
--  للكيلومترات، مع إن الوقت فات.
--
--  الحل: "أيًا منهم أسبق" — overdue لو الكيلومتر وصل الحد *أو* الوقت
--  وصل الحد، وdue_soon لو أي واحد منهم قرّب (90%) من غير ما يوصل.
--  نفس شكل الإرجاع بالظبط (CREATE OR REPLACE من غير تغيير أي بارامتر
--  أو عمود، فمفيش خطر ambiguous-overload ولا داعي لتعديل أي كود
--  Flutter/admin بيستهلك الدالة دي).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.get_maintenance_due_status(p_driver_phone text)
returns table (
  item_key text, label_ar text, importance text, interval_km numeric, interval_months numeric,
  last_done_at timestamptz, last_done_odometer numeric, current_odometer numeric,
  km_since numeric, status text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_current_odometer numeric;
begin
  select max(odometer_km) into v_current_odometer
    from public.vehicle_service_logs
   where driver_phone in (
     p_driver_phone,
     case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
     case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end
   )
   and odometer_km is not null;

  return query
    select
      c.item_key, c.label_ar, c.importance, c.interval_km, c.interval_months,
      ld.last_done_at, ld.last_done_odometer, v_current_odometer,
      case when ld.last_done_odometer is not null and v_current_odometer is not null
           then v_current_odometer - ld.last_done_odometer
           else null end as km_since,
      case
        when ld.last_done_at is null then 'never_done'
        -- Neither dimension trackable (no interval set at all, or no
        -- usable baseline) — nothing to compare against.
        when c.interval_km is null and c.interval_months is null then 'ok'
        -- Overdue if EITHER the distance or the time threshold has
        -- actually been crossed, whichever comes first.
        when (c.interval_km is not null and v_current_odometer is not null and ld.last_done_odometer is not null
              and (v_current_odometer - ld.last_done_odometer) >= c.interval_km)
          or (c.interval_months is not null
              and extract(epoch from (now() - ld.last_done_at)) / (30.436875 * 86400) >= c.interval_months)
          then 'overdue'
        -- Due soon if either dimension is within 90% of its threshold.
        when (c.interval_km is not null and v_current_odometer is not null and ld.last_done_odometer is not null
              and (v_current_odometer - ld.last_done_odometer) >= c.interval_km * 0.9)
          or (c.interval_months is not null
              and extract(epoch from (now() - ld.last_done_at)) / (30.436875 * 86400) >= c.interval_months * 0.9)
          then 'due_soon'
        else 'ok'
      end as status
      from public.maintenance_catalog_items c
      left join lateral (
        select l.performed_at as last_done_at, l.odometer_km as last_done_odometer
          from public.vehicle_service_logs l
         where l.driver_phone in (
                 p_driver_phone,
                 case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
                 case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end
               )
           and l.service_type = 'maintenance'
           and l.maintenance_items is not null
           and c.item_key = any(l.maintenance_items)
         order by l.performed_at desc
         limit 1
      ) ld on true
     where c.active = true
     order by c.sort_order;
end;
$$;
grant execute on function public.get_maintenance_due_status(text) to anon, authenticated;
