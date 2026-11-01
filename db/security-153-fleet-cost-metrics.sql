-- =====================================================================
--  وصّلها — Security #153: مؤشرات تكلفة الأسطول (سعر البنزين + مصاريف
--  الصيانة) — آخر 30 يوم مقابل الـ30 يوم اللي قبلها
--
--  الهدف: الأدمن يقدر يكتشف ارتفاع سعر البنزين أو ارتفاع مصاريف
--  الصيانة بسرعة من بيانات حقيقية بيسجّلها السواقين بنفسهم (مش تخمين)،
--  عشان يقرر هل يرفع الأجرة/العمولة ولا لأ وبأي مقدار. مقارنة آخر 30
--  يوم بالـ30 يوم اللي قبلها بتوضّح الاتجاه (طالع/نازل) مش بس رقم
--  لحظي.
--
--  4 مؤشرات:
--  - avg_fuel_price_per_liter: متوسط سعر اللتر من سجلات الوقود الفعلية.
--  - total_fuel_spend: إجمالي إنفاق الوقود.
--  - total_maintenance_spend: إجمالي إنفاق كل أنواع الصيانة (صيانة
--    دورية/زيت/كاوتش/فحص/تانية) — ده بيلتقط ارتفاع التكلفة سواء كان
--    سببه سعر أعلى أو تكرار أكتر.
--  - maintenance_entries_count: عدد عمليات الصيانة (إشارة على الحجم،
--    مش بس القيمة).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.admin_get_fleet_cost_metrics(p_admin_phone text, p_admin_password text)
returns table(metric text, current_value numeric, previous_value numeric, pct_change numeric)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin record;
  v_cur_fuel_avg_price numeric; v_prev_fuel_avg_price numeric;
  v_cur_fuel_spend numeric; v_prev_fuel_spend numeric;
  v_cur_maint_spend numeric; v_prev_maint_spend numeric;
  v_cur_maint_count numeric; v_prev_maint_count numeric;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return;
  end if;

  select avg(price_per_liter), sum(cost)
    into v_cur_fuel_avg_price, v_cur_fuel_spend
    from public.vehicle_service_logs
   where service_type = 'fuel' and performed_at >= now() - interval '30 days';

  select avg(price_per_liter), sum(cost)
    into v_prev_fuel_avg_price, v_prev_fuel_spend
    from public.vehicle_service_logs
   where service_type = 'fuel' and performed_at >= now() - interval '60 days' and performed_at < now() - interval '30 days';

  select sum(cost), count(*)
    into v_cur_maint_spend, v_cur_maint_count
    from public.vehicle_service_logs
   where service_type in ('maintenance','oil','tire','inspection','other')
     and performed_at >= now() - interval '30 days';

  select sum(cost), count(*)
    into v_prev_maint_spend, v_prev_maint_count
    from public.vehicle_service_logs
   where service_type in ('maintenance','oil','tire','inspection','other')
     and performed_at >= now() - interval '60 days' and performed_at < now() - interval '30 days';

  return query
    select 'avg_fuel_price_per_liter'::text, v_cur_fuel_avg_price, v_prev_fuel_avg_price,
           case when v_prev_fuel_avg_price is null or v_prev_fuel_avg_price = 0 then null
                else round((v_cur_fuel_avg_price - v_prev_fuel_avg_price) / v_prev_fuel_avg_price * 100, 1) end
    union all
    select 'total_fuel_spend'::text, v_cur_fuel_spend, v_prev_fuel_spend,
           case when v_prev_fuel_spend is null or v_prev_fuel_spend = 0 then null
                else round((v_cur_fuel_spend - v_prev_fuel_spend) / v_prev_fuel_spend * 100, 1) end
    union all
    select 'total_maintenance_spend'::text, v_cur_maint_spend, v_prev_maint_spend,
           case when v_prev_maint_spend is null or v_prev_maint_spend = 0 then null
                else round((v_cur_maint_spend - v_prev_maint_spend) / v_prev_maint_spend * 100, 1) end
    union all
    select 'maintenance_entries_count'::text, v_cur_maint_count, v_prev_maint_count,
           case when v_prev_maint_count is null or v_prev_maint_count = 0 then null
                else round((v_cur_maint_count - v_prev_maint_count) / v_prev_maint_count * 100, 1) end;
end;
$$;
grant execute on function public.admin_get_fleet_cost_metrics(text, text) to anon, authenticated;
