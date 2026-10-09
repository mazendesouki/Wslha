-- =====================================================================
--  وصّلها — Security #122: قفل driver_applications/merchant_applications
--
--  من مراجعة أمنية شاملة ("Cyber Security App Test"): الجدولين دول من
--  أول supabase-schema.sql لسه بـ:
--    FOR SELECT USING (true)   -- أي حد بالـ anon key يقدر يقرا كل
--                                  الصفوف: الاسم بالكامل، الرقم القومي،
--                                  صور البطاقة/الرخصة/الفيش، لكل متقدم.
--    (مفيش UPDATE policy صريحة، يعني الافتراضي PostgREST بيسمح بالتحديث
--     كامل لأي عمود — بما فيه status — لأي صف تطابق فلتر الـ phone، من
--     غير أي تحقق ملكية)
--  النتيجة: أي حد يقدر:
--   1) يعمل PATCH .../driver_applications?phone=eq.<رقمه> {"status":"approved"}
--      ويوافق نفسه كسائق من غير ما حد من الأدمن يراجع طلبه خالص —
--      accept_dispatch_offer() (security-15) بيثق في status ده بالكامل.
--   2) يعمل GET .../driver_applications?select=national_id_number,...
--      ويطلع بيانات هوية كل المتقدمين (سواق + تجار) دفعة واحدة.
--
--  الإصلاح:
--   1) تريجر guard_application_status: يمنع أي تغيير مباشر لـ status
--      غير "الرجوع لـ pending" (إعادة تقديم بعد الرفض — ده آمن ومرغوب)
--      إلا لو جاي من داخل admin_review_application نفسها (عن طريق علم
--      transaction-local، مش عمود/صلاحية — يعني الدالة دي بس تقدر
--      توافق/ترفض فعليًا).
--   2) revoke select — القراءة بقت بس عن طريق دوال محصورة (صاحب الطلب
--      نفسه، أو شارة عامة محدودة لسائق معتمد تظهر للعميل، أو الأدمن
--      بالباسورد زي باقي الدوال في المشروع).
--
--  INSERT/UPDATE (غير status) فضلوا من غير تغيير — تسجيل سائق/تاجر
--  جديد وتحديث بيانات المركبة لسه شغالين زي ما هما بالظبط، من غير أي
--  تعديل مطلوب في تدفق driver.astro/merchant-apply.astro.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) حماية عمود status من أي تعديل مباشر غير "رجوع لـ pending".
-- ---------------------------------------------------------------------
create or replace function public._guard_application_status()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  -- العلم ده بيتظبط فقط من جوّه admin_review_application، ومحلي
  -- للـ transaction الحالية (set_config الوسيط الثالث = true) — يعني
  -- مستحيل يفضل متفعّل لأي استدعاء تاني بعد ما الدالة الموثوقة تخلص.
  if coalesce(current_setting('wslha.allow_status_change', true), '') = 'on' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status is distinct from 'pending' then
      new.status := 'pending';
    end if;
  else
    if new.status is distinct from old.status and new.status is distinct from 'pending' then
      new.status := old.status;
    end if;
  end if;
  return new;
end;
$$;

create or replace trigger trg_guard_driver_app_status
  before insert or update on public.driver_applications
  for each row execute function public._guard_application_status();

create or replace trigger trg_guard_merchant_app_status
  before insert or update on public.merchant_applications
  for each row execute function public._guard_application_status();

-- ---------------------------------------------------------------------
-- 2) إعادة كتابة admin_review_application (كانت موجودة بالفعل على
--    قاعدة البيانات الحية من غير أي ملف migration موافق لها في الكود —
--    بتنعاد كتابتها هنا بالظبط بمنطقها الحالي + سطر واحد بيفعّل علم
--    التجاوز قبل كل UPDATE على status).
-- ---------------------------------------------------------------------
create or replace function public.admin_review_application(
  p_admin_phone text, p_admin_password text, p_type text, p_phone text,
  p_status text, p_reason text default null
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin record;
  v_local text;
  v_intl  text;
  v_rows  int;
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

  if p_status not in ('approved', 'rejected') then
    raise exception 'invalid status: %', p_status;
  end if;
  if p_type not in ('driver', 'merchant') then
    raise exception 'invalid type: %', p_type;
  end if;

  v_local := case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end;
  v_intl  := case when p_phone like '0%'   then '+2'||p_phone           else p_phone end;

  perform set_config('wslha.allow_status_change', 'on', true);

  if p_type = 'driver' then
    update public.driver_applications
       set status = p_status, rejection_reason = p_reason, updated_at = now()
     where phone in (v_local, v_intl);
    get diagnostics v_rows = row_count;

    if p_status = 'approved' then
      update public.accounts set role = 'driver', status = 'approved'
       where phone in (v_local, v_intl);
    end if;
  else
    update public.merchant_applications
       set status = p_status, updated_at = now()
     where phone in (v_local, v_intl);
    get diagnostics v_rows = row_count;

    if p_status = 'approved' then
      update public.accounts set role = 'merchant', status = 'approved'
       where phone in (v_local, v_intl);
    end if;
  end if;

  return v_rows > 0;
end;
$$;

grant execute on function public.admin_review_application(text, text, text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) قفل القراءة المباشرة، وفتح دوال محصورة بدلها.
-- ---------------------------------------------------------------------
revoke select on public.driver_applications from anon, authenticated;
revoke select on public.merchant_applications from anon, authenticated;

-- صاحب الطلب نفسه — كل بياناته (نفس الأعمدة اللي كانت متاحة له على أي
-- حال عبر القراءة المفتوحة قبل كده، لكن دلوقتي محصورة برقمه بس).
create or replace function public.get_my_driver_application(p_phone text)
returns setof public.driver_applications
language sql
security definer
set search_path = public, extensions
as $$
  select * from public.driver_applications
   where phone = p_phone
   order by created_at desc
   limit 1;
$$;
grant execute on function public.get_my_driver_application(text) to anon, authenticated;

create or replace function public.get_my_merchant_application(p_phone text)
returns setof public.merchant_applications
language sql
security definer
set search_path = public, extensions
as $$
  select * from public.merchant_applications
   where phone = p_phone
   order by created_at desc
   limit 1;
$$;
grant execute on function public.get_my_merchant_application(text) to anon, authenticated;

-- شارة عامة لسائق معتمد بس (بدون أي بيانات هوية) — تظهر للعميل في شاشة
-- تتبّع الرحلة.
create or replace function public.get_approved_driver_badge(p_driver_phone text)
returns table(
  full_name text, driver_photo_url text, vehicle_model text, vehicle_color text,
  vehicle_year text, has_ac boolean, is_clean boolean
)
language sql
security definer
set search_path = public, extensions
as $$
  select full_name, driver_photo_url, vehicle_model, vehicle_color, vehicle_year, has_ac, is_clean
    from public.driver_applications
   where phone = p_driver_phone and status = 'approved'
   order by created_at desc
   limit 1;
$$;
grant execute on function public.get_approved_driver_badge(text) to anon, authenticated;

-- نفس الشارة العامة، لكن بأعمدة أوسع (فئة/رقم اللوحة/صورة المركبة
-- الأمامية) — تستخدمها شاشة تتبّع الرحلة في تطبيق Flutter
-- (ride_repository.dart's fetchDriverProfile)، لسه من غير أي بيانات
-- هوية (رقم قومي/صور بطاقة/رخصة).
create or replace function public.get_approved_driver_detail(p_driver_phone text)
returns table(
  full_name text, driver_photo_url text, vehicle_category text, vehicle_model text, vehicle_color text,
  vehicle_year text, vehicle_reg_number text, vehicle_front_url text, has_ac boolean, is_clean boolean
)
language sql
security definer
set search_path = public, extensions
as $$
  select full_name, driver_photo_url, vehicle_category, vehicle_model, vehicle_color,
         vehicle_year, vehicle_reg_number, vehicle_front_url, has_ac, is_clean
    from public.driver_applications
   where phone = p_driver_phone and status = 'approved'
   order by created_at desc
   limit 1;
$$;
grant execute on function public.get_approved_driver_detail(text) to anon, authenticated;

-- كاتالوج المركبات المعتمدة (بدون أي ربط برقم تليفون) — لقائمة اختيار
-- المركبة في حجز المطار.
create or replace function public.get_available_driver_vehicles()
returns table(vehicle_category text, vehicle_model text, vehicle_year text)
language sql
security definer
set search_path = public, extensions
as $$
  select vehicle_category, vehicle_model, vehicle_year
    from public.driver_applications
   where status = 'approved';
$$;
grant execute on function public.get_available_driver_vehicles() to anon, authenticated;

-- تحديث علم جودة واحد (has_ac/is_clean/is_modern) — بديل التحديث المباشر
-- اللي كان بيمر زي ما هو من غير أي تحقق (اسم العمود كان بييجي من العميل
-- حرفيًا، لكن القيمة المفروضة واحدة من تلاتة بس، فمفيش SQL injection
-- فعلي، بس التحديث المباشر نفسه كان مش لازم يكون مسموح بيه أصلاً).
create or replace function public.update_driver_quality_flag(p_phone text, p_column text, p_value boolean)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_column not in ('has_ac', 'is_clean', 'is_modern') then
    raise exception 'invalid column: %', p_column;
  end if;
  if p_column = 'has_ac' then
    update public.driver_applications set has_ac = p_value, updated_at = now() where phone = p_phone;
  elsif p_column = 'is_clean' then
    update public.driver_applications set is_clean = p_value, updated_at = now() where phone = p_phone;
  else
    update public.driver_applications set is_modern = p_value, updated_at = now() where phone = p_phone;
  end if;
end;
$$;
grant execute on function public.update_driver_quality_flag(text, text, boolean) to anon, authenticated;

-- حفظ رقم اللوحة/صورتها (driver-dashboard.astro) — بديل الـ PATCH المباشر.
create or replace function public.update_driver_plate_info(p_phone text, p_vehicle_reg_number text, p_plate_photo_url text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.driver_applications
     set vehicle_reg_number = coalesce(p_vehicle_reg_number, vehicle_reg_number),
         plate_photo_url = coalesce(p_plate_photo_url, plate_photo_url),
         updated_at = now()
   where phone = p_phone;
end;
$$;
grant execute on function public.update_driver_plate_info(text, text, text) to anon, authenticated;

-- الأدمن — نفس نمط admin_list_coupons/admin_list_wallets.
create or replace function public.admin_list_applications(p_admin_phone text, p_admin_password text, p_type text)
returns setof jsonb
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

  if p_type = 'driver' then
    return query select to_jsonb(d.*) from public.driver_applications d order by d.created_at desc limit 500;
  elsif p_type = 'merchant' then
    return query select to_jsonb(m.*) from public.merchant_applications m order by m.created_at desc limit 500;
  else
    raise exception 'invalid type: %', p_type;
  end if;
end;
$$;
grant execute on function public.admin_list_applications(text, text, text) to anon, authenticated;

create or replace function public.admin_get_application(p_admin_phone text, p_admin_password text, p_type text, p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_row jsonb;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return null; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return null;
  end if;

  if p_type = 'driver' then
    select to_jsonb(d.*) into v_row from public.driver_applications d
     where d.phone = p_phone order by d.created_at desc limit 1;
  elsif p_type = 'merchant' then
    select to_jsonb(m.*) into v_row from public.merchant_applications m
     where m.phone = p_phone order by m.created_at desc limit 1;
  else
    raise exception 'invalid type: %', p_type;
  end if;
  return v_row;
end;
$$;
grant execute on function public.admin_get_application(text, text, text, text) to anon, authenticated;
