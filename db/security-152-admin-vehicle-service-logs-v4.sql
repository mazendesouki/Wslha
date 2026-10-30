-- =====================================================================
--  وصّلها — Security #152: admin_list_vehicle_service_logs_v4 — إضافة
--  عمود مركز/ورشة الصيانة
--
--  security-150 أضاف service_center لجدول vehicle_service_logs — شكل
--  الإرجاع اتغيّر فعلاً، فـ CREATE OR REPLACE العادي مش هيكفي (ده
--  محتاج اسم جديد للدالة، مش rename، لأن المشكلة هنا مختلفة عن إضافة
--  باراميتر: التابع admin_list_vehicle_service_logs_v3 شكل الإرجاع
--  بتاعه (RETURNS TABLE columns) لازم يتغيّر، وده حاجة CREATE OR
--  REPLACE مينفعش يعملها خالص — نفس السبب اللي خلّى v2→v3 قبل كده).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.admin_list_vehicle_service_logs_v4(
  p_admin_phone text, p_admin_password text,
  p_driver_phone text default null, p_service_type text default null,
  p_limit integer default 300
)
returns table(
  id uuid, driver_phone text, driver_name text, service_type text, custom_label text,
  cost numeric, odometer_km numeric, fuel_liters numeric, price_per_liter numeric,
  quantity numeric, unit_price numeric, service_center text, notes text,
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
           l.cost, l.odometer_km, l.fuel_liters, l.price_per_liter, l.quantity, l.unit_price,
           l.service_center, l.notes, l.performed_at, l.created_by, l.created_at
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
grant execute on function public.admin_list_vehicle_service_logs_v4(text, text, text, text, integer) to anon, authenticated;
