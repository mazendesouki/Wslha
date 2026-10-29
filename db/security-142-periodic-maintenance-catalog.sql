-- =====================================================================
--  وصّلها — Security #142: نظام الصيانة الدورية (البنود + التوقيت +
--  الأهمية + تتبّع الاستحقاق)
--
--  بند "صيانة دورية" في vehicle_service_logs كان مجرد تكلفة إجمالية
--  وملاحظة حرة، من غير تحديد إيه اللي اتعمل بالظبط. النظام ده بيضيف
--  كتالوج ثابت (قابل للتعديل من لوحة الإدارة) لبنود الصيانة القياسية
--  — كل بند له أهمية (حرجة/مهمة) وفترة موصى بيها بالكيلومتر (وبالشهور
--  لو مناسب)، وسجل الصيانة بقى يسجّل أي بنود اتعملت فعليًا في الزيارة
--  دي، والتطبيق بيحسب الاستحقاق (متأخر/قرّب/تمام) بناءً على آخر مرة
--  اتعمل فيها كل بند مقارنة بعداد الكيلومترات الحالي — من غير أي
--  تسجيل جديد، فقط من بيانات السائق الموجودة أصلًا.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.maintenance_catalog_items (
  id uuid primary key default gen_random_uuid(),
  item_key text unique not null,
  label_ar text not null,
  importance text not null check (importance in ('critical','important')),
  interval_km numeric,
  interval_months numeric,
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
revoke all on public.maintenance_catalog_items from anon, authenticated;

insert into public.maintenance_catalog_items (item_key, label_ar, importance, interval_km, interval_months, sort_order) values
  ('oil_filter',          'تغيير فلتر الزيت',          'critical',  7000,  null, 1),
  ('air_filter',          'فلتر الهواء',                'important', 15000, null, 2),
  ('fuel_filter',         'فلتر البنزين',               'important', 25000, null, 3),
  ('spark_plugs',         'البوجيهات',                  'important', 30000, null, 4),
  ('brake_pads',          'تيل الفرامل',                'critical',  15000, null, 5),
  ('brake_fluid',         'زيت الفرامل',                'critical',  40000, 24,   6),
  ('timing_belt',         'سير الكاتينة/التايمنج',      'critical',  80000, null, 7),
  ('battery',             'البطارية',                   'important', 20000, 24,   8),
  ('coolant',             'سائل التبريد',               'important', 40000, 24,   9),
  ('transmission_fluid',  'زيت الجير',                  'important', 80000, null, 10),
  ('shock_absorbers',     'المساعدين (الكاتم)',         'important', 60000, null, 11)
on conflict (item_key) do nothing;

-- ---------------------------------------------------------------------
-- 1) كتالوج الصيانة — قراءة عامة (كل سائق محتاجها عشان يعرف يختار
--    البنود وقت تسجيل عملية صيانة).
-- ---------------------------------------------------------------------
create or replace function public.list_maintenance_catalog()
returns setof public.maintenance_catalog_items
language sql
security definer
set search_path = public, extensions
as $$
  select * from public.maintenance_catalog_items where active = true order by sort_order;
$$;
grant execute on function public.list_maintenance_catalog() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) إضافة maintenance_items لسجل الخدمة — أي بنود اتعملت في زيارة
--    الصيانة دي (مصفوفة من item_key).
-- ---------------------------------------------------------------------
alter table public.vehicle_service_logs add column if not exists maintenance_items text[];

do $$
begin
  if exists (
    select 1 from pg_proc p
     where p.proname = 'log_vehicle_service'
       and pg_get_function_identity_arguments(p.oid) =
           'p_driver_phone text, p_service_type text, p_custom_label text, p_cost numeric, p_odometer_km numeric, p_fuel_liters numeric, p_notes text, p_performed_at timestamp with time zone, p_price_per_liter numeric, p_quantity numeric, p_unit_price numeric'
  ) then
    alter function public.log_vehicle_service(text, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric) rename to log_vehicle_service_deprecated_v3;
    revoke all on function public.log_vehicle_service_deprecated_v3(text, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric) from anon, authenticated;
  end if;
end $$;

create or replace function public.log_vehicle_service(
  p_driver_phone text,
  p_service_type text,
  p_custom_label text default null,
  p_cost numeric default null,
  p_odometer_km numeric default null,
  p_fuel_liters numeric default null,
  p_notes text default null,
  p_performed_at timestamptz default now(),
  p_price_per_liter numeric default null,
  p_quantity numeric default null,
  p_unit_price numeric default null,
  p_maintenance_items text[] default null
)
returns public.vehicle_service_logs
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_row public.vehicle_service_logs; v_cost numeric := p_cost;
begin
  if p_driver_phone is null or p_driver_phone = '' then
    raise exception 'driver_phone_required';
  end if;
  if not exists (
    select 1 from public.driver_applications
     where phone::text in (
       p_driver_phone,
       case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
       case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end
     )
  ) then
    raise exception 'driver_not_found';
  end if;
  if p_price_per_liter is not null and p_price_per_liter < 0 then raise exception 'invalid_price_per_liter'; end if;
  if p_odometer_km is not null and p_odometer_km < 0 then raise exception 'invalid_odometer'; end if;
  if p_fuel_liters is not null and p_fuel_liters < 0 then raise exception 'invalid_fuel_liters'; end if;
  if p_quantity is not null and p_quantity < 0 then raise exception 'invalid_quantity'; end if;
  if p_unit_price is not null and p_unit_price < 0 then raise exception 'invalid_unit_price'; end if;

  if v_cost is null and p_price_per_liter is not null and p_fuel_liters is not null then
    v_cost := round(p_price_per_liter * p_fuel_liters, 2);
  elsif v_cost is null and p_quantity is not null and p_unit_price is not null then
    v_cost := round(p_quantity * p_unit_price, 2);
  end if;
  if v_cost is not null and v_cost < 0 then raise exception 'invalid_cost'; end if;

  insert into public.vehicle_service_logs
    (driver_phone, service_type, custom_label, cost, odometer_km, fuel_liters, price_per_liter, quantity, unit_price, maintenance_items, notes, performed_at, created_by)
  values
    (p_driver_phone, p_service_type, nullif(trim(coalesce(p_custom_label,'')), ''), v_cost, p_odometer_km, p_fuel_liters, p_price_per_liter, p_quantity, p_unit_price, p_maintenance_items, nullif(trim(coalesce(p_notes,'')), ''), coalesce(p_performed_at, now()), p_driver_phone)
  returning * into v_row;

  return v_row;
end;
$$;
grant execute on function public.log_vehicle_service(text, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric, text[]) to anon, authenticated;

do $$
begin
  if exists (
    select 1 from pg_proc p
     where p.proname = 'update_vehicle_service_log'
       and pg_get_function_identity_arguments(p.oid) =
           'p_driver_phone text, p_log_id uuid, p_service_type text, p_custom_label text, p_cost numeric, p_odometer_km numeric, p_fuel_liters numeric, p_notes text, p_performed_at timestamp with time zone, p_price_per_liter numeric, p_quantity numeric, p_unit_price numeric'
  ) then
    alter function public.update_vehicle_service_log(text, uuid, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric) rename to update_vehicle_service_log_deprecated_v2;
    revoke all on function public.update_vehicle_service_log_deprecated_v2(text, uuid, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric) from anon, authenticated;
  end if;
end $$;

create or replace function public.update_vehicle_service_log(
  p_driver_phone text,
  p_log_id uuid,
  p_service_type text,
  p_custom_label text default null,
  p_cost numeric default null,
  p_odometer_km numeric default null,
  p_fuel_liters numeric default null,
  p_notes text default null,
  p_performed_at timestamptz default now(),
  p_price_per_liter numeric default null,
  p_quantity numeric default null,
  p_unit_price numeric default null,
  p_maintenance_items text[] default null
)
returns public.vehicle_service_logs
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_row public.vehicle_service_logs; v_cost numeric := p_cost;
begin
  if p_price_per_liter is not null and p_price_per_liter < 0 then raise exception 'invalid_price_per_liter'; end if;
  if p_odometer_km is not null and p_odometer_km < 0 then raise exception 'invalid_odometer'; end if;
  if p_fuel_liters is not null and p_fuel_liters < 0 then raise exception 'invalid_fuel_liters'; end if;
  if p_quantity is not null and p_quantity < 0 then raise exception 'invalid_quantity'; end if;
  if p_unit_price is not null and p_unit_price < 0 then raise exception 'invalid_unit_price'; end if;

  if v_cost is null and p_price_per_liter is not null and p_fuel_liters is not null then
    v_cost := round(p_price_per_liter * p_fuel_liters, 2);
  elsif v_cost is null and p_quantity is not null and p_unit_price is not null then
    v_cost := round(p_quantity * p_unit_price, 2);
  end if;
  if v_cost is not null and v_cost < 0 then raise exception 'invalid_cost'; end if;

  update public.vehicle_service_logs
     set service_type = p_service_type,
         custom_label = nullif(trim(coalesce(p_custom_label,'')), ''),
         cost = v_cost,
         odometer_km = p_odometer_km,
         fuel_liters = p_fuel_liters,
         price_per_liter = p_price_per_liter,
         quantity = p_quantity,
         unit_price = p_unit_price,
         maintenance_items = p_maintenance_items,
         notes = nullif(trim(coalesce(p_notes,'')), ''),
         performed_at = coalesce(p_performed_at, performed_at)
   where id = p_log_id
     and driver_phone in (
       p_driver_phone,
       case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
       case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end
     )
  returning * into v_row;

  if v_row.id is null then raise exception 'log_not_found'; end if;
  return v_row;
end;
$$;
grant execute on function public.update_vehicle_service_log(text, uuid, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric, text[]) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) حالة الاستحقاق — لكل بند في الكتالوج: آخر مرة اتعمل، الكيلومترات
--    اللي عدت من وقتها (مقارنة بأحدث عداد كيلومترات مسجّل للسائق)،
--    والحالة (overdue/due_soon/ok/never_done).
-- ---------------------------------------------------------------------
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
    select c.item_key, c.label_ar, c.importance, c.interval_km, c.interval_months,
           ld.last_done_at, ld.last_done_odometer, v_current_odometer,
           case when ld.last_done_odometer is not null and v_current_odometer is not null
                then v_current_odometer - ld.last_done_odometer
                else null end as km_since,
           case
             when ld.last_done_at is null then 'never_done'
             when c.interval_km is null or v_current_odometer is null or ld.last_done_odometer is null then 'ok'
             when (v_current_odometer - ld.last_done_odometer) >= c.interval_km then 'overdue'
             when (v_current_odometer - ld.last_done_odometer) >= c.interval_km * 0.9 then 'due_soon'
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

-- ---------------------------------------------------------------------
-- 4) إدارة الكتالوج من لوحة الإدارة.
-- ---------------------------------------------------------------------
create or replace function public.admin_list_maintenance_catalog(p_admin_phone text, p_admin_password text)
returns setof public.maintenance_catalog_items
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return;
  end if;

  return query select * from public.maintenance_catalog_items order by sort_order;
end;
$$;
grant execute on function public.admin_list_maintenance_catalog(text, text) to anon, authenticated;

create or replace function public.admin_upsert_maintenance_catalog_item(
  p_admin_phone text, p_admin_password text,
  p_item_key text, p_label_ar text, p_importance text,
  p_interval_km numeric, p_interval_months numeric,
  p_sort_order int default 0, p_active boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return false; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;
  if p_importance not in ('critical','important') then raise exception 'invalid_importance'; end if;

  insert into public.maintenance_catalog_items
    (item_key, label_ar, importance, interval_km, interval_months, sort_order, active, updated_at)
  values
    (p_item_key, p_label_ar, p_importance, p_interval_km, p_interval_months, p_sort_order, p_active, now())
  on conflict (item_key) do update
    set label_ar = excluded.label_ar,
        importance = excluded.importance,
        interval_km = excluded.interval_km,
        interval_months = excluded.interval_months,
        sort_order = excluded.sort_order,
        active = excluded.active,
        updated_at = now();

  return true;
end;
$$;
grant execute on function public.admin_upsert_maintenance_catalog_item(text, text, text, text, text, numeric, numeric, int, boolean) to anon, authenticated;
