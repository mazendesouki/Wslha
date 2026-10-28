-- =====================================================================
--  وصّلها — Security #140: حساب سعر الوحدة × الكمية لخدمات الزيت والكاوتش
--
--  نفس نمط الوقود (سعر اللتر × عدد اللترات) بيتطبق على:
--  - الزيت: سعر اللتر × عدد اللترات.
--  - الكاوتش: سعر الكاوتش الواحد × العدد.
--  الصيانة الدورية وفحص المحرك والخدمات التانية بتفضل مبلغ إجمالي ثابت
--  زي ما هي (مفيش وحدة طبيعية واحدة تنطبق عليهم كلهم).
--
--  أعمدة عامة جديدة (quantity, unit_price) بدل تكرار fuel_liters/
--  price_per_liter لأنواع تانية — عشان أعمدة الوقود تفضل مخصصة للوقود
--  فعلاً (الاسم بيوصف المحتوى صح)، والزيت/الكاوتش ليهم عمودين عامين
--  منفصلين.
--
--  مهم: إضافة بارامتر جديد لدالة موجودة بـ CREATE OR REPLACE بيخلق
--  نسخة (overload) تانية بدل ما يستبدل القديمة (هي بالظبط المشكلة اللي
--  اتصلحت في security-138) — فبننقل كل نسخة قديمة لاسم deprecated
--  الأول (ALTER FUNCTION RENAME، مش DROP)، وبعدين ننشئ النسخة الجديدة
--  بنفس الاسم الأصلي. admin_list_vehicle_service_logs_v2 شكل
--  الأعمدة المرجعة بتاعها هيتغيّر، فبتاخد اسم v3 جديد بدل ما تتعدل في
--  مكانها (CREATE OR REPLACE مش بيسمح بتغيير شكل الأعمدة أصلًا).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.vehicle_service_logs add column if not exists quantity numeric;
alter table public.vehicle_service_logs add column if not exists unit_price numeric;

-- ---------------------------------------------------------------------
-- 1) log_vehicle_service — نسخة جديدة بـ quantity/unit_price، والقديمة
--    (9 بارامترات) بتتنقل لاسم deprecated.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_proc p
     where p.proname = 'log_vehicle_service'
       and pg_get_function_identity_arguments(p.oid) =
           'p_driver_phone text, p_service_type text, p_custom_label text, p_cost numeric, p_odometer_km numeric, p_fuel_liters numeric, p_notes text, p_performed_at timestamp with time zone, p_price_per_liter numeric'
  ) then
    alter function public.log_vehicle_service(text, text, text, numeric, numeric, numeric, text, timestamptz, numeric) rename to log_vehicle_service_deprecated_v2;
    revoke all on function public.log_vehicle_service_deprecated_v2(text, text, text, numeric, numeric, numeric, text, timestamptz, numeric) from anon, authenticated;
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
  p_unit_price numeric default null
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
    (driver_phone, service_type, custom_label, cost, odometer_km, fuel_liters, price_per_liter, quantity, unit_price, notes, performed_at, created_by)
  values
    (p_driver_phone, p_service_type, nullif(trim(coalesce(p_custom_label,'')), ''), v_cost, p_odometer_km, p_fuel_liters, p_price_per_liter, p_quantity, p_unit_price, nullif(trim(coalesce(p_notes,'')), ''), coalesce(p_performed_at, now()), p_driver_phone)
  returning * into v_row;

  return v_row;
end;
$$;
grant execute on function public.log_vehicle_service(text, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) update_vehicle_service_log — نفس المبدأ.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_proc p
     where p.proname = 'update_vehicle_service_log'
       and pg_get_function_identity_arguments(p.oid) =
           'p_driver_phone text, p_log_id uuid, p_service_type text, p_custom_label text, p_cost numeric, p_odometer_km numeric, p_fuel_liters numeric, p_notes text, p_performed_at timestamp with time zone, p_price_per_liter numeric'
  ) then
    alter function public.update_vehicle_service_log(text, uuid, text, text, numeric, numeric, numeric, text, timestamptz, numeric) rename to update_vehicle_service_log_deprecated_v1;
    revoke all on function public.update_vehicle_service_log_deprecated_v1(text, uuid, text, text, numeric, numeric, numeric, text, timestamptz, numeric) from anon, authenticated;
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
  p_unit_price numeric default null
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
grant execute on function public.update_vehicle_service_log(text, uuid, text, text, numeric, numeric, numeric, text, timestamptz, numeric, numeric, numeric) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) الأدمن — نسخة v3 بإضافة quantity/unit_price، والقديمة (v2)
--    بتتنقل لاسم deprecated (شكل الأعمدة المرجعة اتغيّر).
-- ---------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_proc p
     where p.proname = 'admin_list_vehicle_service_logs_v2'
  ) then
    alter function public.admin_list_vehicle_service_logs_v2(text, text, text, text, int) rename to admin_list_vehicle_service_logs_v2_deprecated;
    revoke all on function public.admin_list_vehicle_service_logs_v2_deprecated(text, text, text, text, int) from anon, authenticated;
  end if;
end $$;

create or replace function public.admin_list_vehicle_service_logs_v3(
  p_admin_phone text, p_admin_password text,
  p_driver_phone text default null,
  p_service_type text default null,
  p_limit int default 300
)
returns table (
  id uuid, driver_phone text, driver_name text, service_type text, custom_label text,
  cost numeric, odometer_km numeric, fuel_liters numeric, price_per_liter numeric,
  quantity numeric, unit_price numeric, notes text,
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
           l.cost, l.odometer_km, l.fuel_liters, l.price_per_liter, l.quantity, l.unit_price, l.notes, l.performed_at, l.created_by, l.created_at
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
grant execute on function public.admin_list_vehicle_service_logs_v3(text, text, text, text, int) to anon, authenticated;
