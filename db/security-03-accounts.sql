-- =====================================================================
--  وصّلها — Security #3: تأمين جدول الحسابات من الثغرات الكارثية
--
--  يغلق هجومَين خطيرَين كان مفتاح anon العام يسمح بهما عبر REST مباشرة:
--    (أ) تغيير كلمة مرور أي حساب  →  استيلاء كامل
--    (ب) ترقية أي حساب إلى admin   →  سيطرة كاملة
--
--  بعد التشغيل:
--    • كلمة المرور تتغيّر فقط عبر reset_password (برمز بريد) — لا PATCH مباشر.
--    • role='admin' يُمنح فقط عبر grant_admin/create_admin بعد التحقق من
--      كلمة مرور مشرف موجود.
--    • باقي العمليات (تغيير الحالة، اعتماد سائق/تاجر، تغيير الدور لغير admin)
--      تبقى تعمل كما هي — لا تتعطّل لوحة التحكم.
--
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) مُحفّز الحماية: يمنع تغيير كلمة المرور أو منح admin إلا عبر دالة
--    آمنة (SECURITY DEFINER) تضبط العلم app.privileged='on'.
-- ---------------------------------------------------------------------
create or replace function public.guard_account_privilege()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  -- المسار الآمن (داخل دوالنا) مسموح
  if current_setting('app.privileged', true) = 'on' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.role = 'admin' then
      raise exception 'forbidden: لا يمكن إنشاء حساب admin مباشرة';
    end if;
    return new;
  end if;

  -- UPDATE: احمِ كلمة المرور ومنح الأدمن
  if new.password is distinct from old.password then
    raise exception 'forbidden: كلمة المرور تُغيَّر فقط عبر reset_password';
  end if;
  if new.role is distinct from old.role and new.role = 'admin' then
    raise exception 'forbidden: دور admin يُمنح فقط عبر مشرف موثّق';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_account_privilege on public.accounts;
create trigger trg_guard_account_privilege
  before insert or update on public.accounts
  for each row execute function public.guard_account_privilege();

-- ---------------------------------------------------------------------
-- 2) reset_password: يعمل بصلاحية مرتفعة ليمرّ تغيير كلمة المرور عبر المُحفّز
--    (يتحقق من رمز OTP من جدول otps أولاً — كما هو).
-- ---------------------------------------------------------------------
create or replace function public.reset_password(p_phone text, p_code text, p_new_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare r record; v_local text; v_intl text; v_rows int;
begin
  if p_new_password is null or length(p_new_password) < 8 then raise exception 'weak_password'; end if;
  select * into r from public.otps
   where phone = p_phone and code = p_code and used = false and expires_at > now()
   order by created_at desc limit 1;
  if not found then return false; end if;
  update public.otps set used = true where id = r.id;

  v_local := case when p_phone like '+20%' then '0' || substr(p_phone, 4) else p_phone end;
  v_intl  := case when p_phone like '0%'   then '+2' || p_phone           else p_phone end;

  perform set_config('app.privileged', 'on', true);
  update public.accounts set password = p_new_password where phone in (v_local, v_intl);
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);
  return v_rows > 0;
end;
$$;

-- ---------------------------------------------------------------------
-- 3) grant_admin: ترقية مستخدم إلى admin — فقط بعد التحقق من كلمة مرور
--    مشرف موجود (bcrypt). يمنع الترقية الذاتية عبر anon.
-- ---------------------------------------------------------------------
create or replace function public.grant_admin(p_admin_phone text, p_admin_password text, p_target_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_local text; v_intl text; v_rows int;
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

  v_local := case when p_target_phone like '+20%' then '0'||substr(p_target_phone,4) else p_target_phone end;
  v_intl  := case when p_target_phone like '0%'   then '+2'||p_target_phone           else p_target_phone end;

  perform set_config('app.privileged', 'on', true);
  update public.accounts set role = 'admin', status = 'active' where phone in (v_local, v_intl);
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);
  return v_rows > 0;
end;
$$;

-- ---------------------------------------------------------------------
-- 4) create_admin: إنشاء حساب مشرف جديد — فقط بعد التحقق من مشرف موجود.
-- ---------------------------------------------------------------------
create or replace function public.create_admin(
  p_admin_phone text, p_admin_password text, p_name text, p_phone text, p_password text
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

  perform set_config('app.privileged', 'on', true);
  insert into public.accounts (phone, name, password, role, status, created_at)
  values (p_phone, p_name, p_password, 'admin', 'active', now());  -- password hashed by trigger
  perform set_config('app.privileged', 'off', true);
  return true;
end;
$$;

grant execute on function public.grant_admin(text, text, text) to anon, authenticated;
grant execute on function public.create_admin(text, text, text, text, text) to anon, authenticated;

-- =====================================================================
--  اختبار سريع (اختياري):
--   -- محاولة تزوير عبر anon يجب أن تفشل:
--   -- PATCH /accounts {password:'x'}        → forbidden
--   -- PATCH /accounts {role:'admin'}        → forbidden
--   select public.grant_admin('01102667324','<your_admin_password>','01XXXXXXXXX'); -- true
-- =====================================================================
