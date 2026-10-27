-- =====================================================================
--  وصّلها — Security #134: خدمات المركبات — النواة الأساسية
--
--  قسم "خدمات المركبات" في لوحة التحكم: صيانة دورية وسجل السائق،
--  استهلاك الوقود وحساب التكلفة، تغيير الكاوتش وتكلفته، تتبع تغيير
--  الزيت، فحص/صيانة المحرك، ملف/تاريخ صيانة العربية، وإمكانية إضافة
--  خدمات تانية (service_type = 'other' + custom_label).
--
--  جدول واحد عام (vehicle_service_logs) بدل 5 جداول منفصلة — كل
--  الأنواع (صيانة/وقود/كاوتش/زيت/فحص/أخرى) بتستخدم نفس الأعمدة
--  (التكلفة، عداد الكيلومترات، لتر الوقود للنوع fuel بس)، فمفيش داعي
--  لتكرار البنية 5 مرات، ونفس الـRPCs بتخدم الكل. السائق بيسجل من
--  التطبيق، والأدمن بيشوف/يراجع من اللوحة.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.vehicle_service_logs (
  id uuid primary key default gen_random_uuid(),
  driver_phone text not null,
  service_type text not null check (service_type in ('maintenance','fuel','tire','oil','inspection','other')),
  custom_label text,
  cost numeric,
  odometer_km numeric,
  fuel_liters numeric,
  notes text,
  performed_at timestamptz not null default now(),
  created_by text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_vehicle_service_logs_driver on public.vehicle_service_logs (driver_phone, performed_at desc);
revoke all on public.vehicle_service_logs from anon, authenticated;

-- ---------------------------------------------------------------------
-- 1) السائق يسجل عملية جديدة.
-- ---------------------------------------------------------------------
create or replace function public.log_vehicle_service(
  p_driver_phone text,
  p_service_type text,
  p_custom_label text default null,
  p_cost numeric default null,
  p_odometer_km numeric default null,
  p_fuel_liters numeric default null,
  p_notes text default null,
  p_performed_at timestamptz default now()
)
returns public.vehicle_service_logs
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_row public.vehicle_service_logs;
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
  if p_cost is not null and p_cost < 0 then raise exception 'invalid_cost'; end if;
  if p_odometer_km is not null and p_odometer_km < 0 then raise exception 'invalid_odometer'; end if;
  if p_fuel_liters is not null and p_fuel_liters < 0 then raise exception 'invalid_fuel_liters'; end if;

  insert into public.vehicle_service_logs
    (driver_phone, service_type, custom_label, cost, odometer_km, fuel_liters, notes, performed_at, created_by)
  values
    (p_driver_phone, p_service_type, nullif(trim(coalesce(p_custom_label,'')), ''), p_cost, p_odometer_km, p_fuel_liters, nullif(trim(coalesce(p_notes,'')), ''), coalesce(p_performed_at, now()), p_driver_phone)
  returning * into v_row;

  return v_row;
end;
$$;
grant execute on function public.log_vehicle_service(text, text, text, numeric, numeric, numeric, text, timestamptz) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) السائق يشوف سجله هو بس (ملف/تاريخ الصيانة).
-- ---------------------------------------------------------------------
create or replace function public.list_my_vehicle_service_logs(
  p_driver_phone text,
  p_service_type text default null,
  p_limit int default 200
)
returns setof public.vehicle_service_logs
language sql
security definer
set search_path = public, extensions
as $$
  select * from public.vehicle_service_logs
   where driver_phone in (
       p_driver_phone,
       case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
       case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end
     )
     and (p_service_type is null or service_type = p_service_type)
   order by performed_at desc
   limit greatest(1, least(coalesce(p_limit, 200), 500));
$$;
grant execute on function public.list_my_vehicle_service_logs(text, text, int) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) السائق يلغي سجل غلط سجّله هو بنفسه.
-- ---------------------------------------------------------------------
create or replace function public.delete_my_vehicle_service_log(p_driver_phone text, p_log_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_deleted boolean;
begin
  delete from public.vehicle_service_logs
   where id = p_log_id
     and driver_phone in (
       p_driver_phone,
       case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
       case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end
     )
  returning true into v_deleted;
  return coalesce(v_deleted, false);
end;
$$;
grant execute on function public.delete_my_vehicle_service_log(text, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) الأدمن يشوف سجلات كل السائقين (مع فلترة اختيارية).
-- ---------------------------------------------------------------------
create or replace function public.admin_list_vehicle_service_logs(
  p_admin_phone text, p_admin_password text,
  p_driver_phone text default null,
  p_service_type text default null,
  p_limit int default 300
)
returns table (
  id uuid, driver_phone text, driver_name text, service_type text, custom_label text,
  cost numeric, odometer_km numeric, fuel_liters numeric, notes text,
  performed_at timestamptz, created_by text, created_at timestamptz
)
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

  return query
    select l.id, l.driver_phone, da.full_name, l.service_type, l.custom_label,
           l.cost, l.odometer_km, l.fuel_liters, l.notes, l.performed_at, l.created_by, l.created_at
      from public.vehicle_service_logs l
      left join lateral (
        select full_name from public.driver_applications da
         where da.phone::text in (
           l.driver_phone,
           case when l.driver_phone like '+20%' then '0'||substr(l.driver_phone,4) else l.driver_phone end,
           case when l.driver_phone like '0%'   then '+2'||l.driver_phone           else l.driver_phone end
         )
         order by da.created_at desc limit 1
      ) da on true
     where (p_driver_phone is null or l.driver_phone = p_driver_phone)
       and (p_service_type is null or l.service_type = p_service_type)
     order by l.performed_at desc
     limit greatest(1, least(coalesce(p_limit, 300), 1000));
end;
$$;
grant execute on function public.admin_list_vehicle_service_logs(text, text, text, text, int) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5) الأدمن يشوف إجمالي التكلفة لكل نوع خدمة (حساب التكلفة الإجمالية).
-- ---------------------------------------------------------------------
create or replace function public.admin_vehicle_service_summary(p_admin_phone text, p_admin_password text)
returns table (service_type text, entries_count bigint, total_cost numeric, total_fuel_liters numeric)
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

  return query
    select l.service_type, count(*)::bigint, coalesce(sum(l.cost), 0), coalesce(sum(l.fuel_liters), 0)
      from public.vehicle_service_logs l
     group by l.service_type
     order by l.service_type;
end;
$$;
grant execute on function public.admin_vehicle_service_summary(text, text) to anon, authenticated;
