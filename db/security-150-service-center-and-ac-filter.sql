-- =====================================================================
--  وصّلها — Security #150: مركز/ورشة الصيانة + فلتر التكييف
--
--  جزء من "سجل خدمة وصيانة المركبة" الموسّع: إضافة اسم الورشة/مركز
--  الصيانة كحقل لكل سجل، وإضافة "فلتر التكييف" كعنصر جديد في كتالوج
--  الصيانة الدورية (كان ناقص من الـ11 عنصر الأصليين).
--
--  log_vehicle_service/update_vehicle_service_log لازم تتعدّل بإضافة
--  p_service_center — زي كل مرة فات، باراميتر جديد بيعمل overload
--  جديد لو اتعمله CREATE OR REPLACE عادي، فاستخدمنا نفس أسلوب rename-
--  then-recreate (security-138/140/142/144) لمنع الباگ ده.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) عمود مركز/ورشة الصيانة.
-- ---------------------------------------------------------------------
alter table public.vehicle_service_logs add column if not exists service_center text;

-- ---------------------------------------------------------------------
-- 2) فلتر التكييف — عنصر جديد في كتالوج الصيانة الدورية.
-- ---------------------------------------------------------------------
insert into public.maintenance_catalog_items (item_key, label_ar, importance, interval_km, interval_months, sort_order)
values ('ac_filter', 'فلتر التكييف', 'important', 15000, 12, 12)
on conflict (item_key) do nothing;

-- ---------------------------------------------------------------------
-- 3) log_vehicle_service — rename القديم، نص جديد مطابق تمامًا للحي
--    زائد p_service_center بس.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_proc p
     where p.proname = 'log_vehicle_service'
       and pg_get_function_identity_arguments(p.oid) =
         'p_driver_phone text, p_service_type text, p_custom_label text, p_cost numeric, p_odometer_km numeric, p_fuel_liters numeric, p_notes text, p_performed_at timestamp with time zone, p_price_per_liter numeric, p_quantity numeric, p_unit_price numeric, p_maintenance_items text[]'
  ) then
    alter function public.log_vehicle_service(
      text, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric, text[]
    ) rename to log_vehicle_service_deprecated_v4;
    revoke all on function public.log_vehicle_service_deprecated_v4(
      text, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric, text[]
    ) from anon, authenticated;
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
  p_maintenance_items text[] default null,
  p_service_center text default null
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
    (driver_phone, service_type, custom_label, cost, odometer_km, fuel_liters, price_per_liter, quantity, unit_price, maintenance_items, notes, performed_at, created_by, service_center)
  values
    (p_driver_phone, p_service_type, nullif(trim(coalesce(p_custom_label,'')), ''), v_cost, p_odometer_km, p_fuel_liters, p_price_per_liter, p_quantity, p_unit_price, p_maintenance_items, nullif(trim(coalesce(p_notes,'')), ''), coalesce(p_performed_at, now()), p_driver_phone, nullif(trim(coalesce(p_service_center,'')), ''))
  returning * into v_row;

  return v_row;
end;
$$;
grant execute on function public.log_vehicle_service(text, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric, text[], text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) update_vehicle_service_log — نفس الأسلوب.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_proc p
     where p.proname = 'update_vehicle_service_log'
       and pg_get_function_identity_arguments(p.oid) =
         'p_driver_phone text, p_log_id uuid, p_service_type text, p_custom_label text, p_cost numeric, p_odometer_km numeric, p_fuel_liters numeric, p_notes text, p_performed_at timestamp with time zone, p_price_per_liter numeric, p_quantity numeric, p_unit_price numeric, p_maintenance_items text[]'
  ) then
    alter function public.update_vehicle_service_log(
      text, uuid, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric, text[]
    ) rename to update_vehicle_service_log_deprecated_v3;
    revoke all on function public.update_vehicle_service_log_deprecated_v3(
      text, uuid, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric, text[]
    ) from anon, authenticated;
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
  p_maintenance_items text[] default null,
  p_service_center text default null
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
         performed_at = coalesce(p_performed_at, performed_at),
         service_center = nullif(trim(coalesce(p_service_center,'')), '')
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
grant execute on function public.update_vehicle_service_log(text, uuid, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric, text[], text) to anon, authenticated;
