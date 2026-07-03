-- =====================================================================
--  وصّلها — Security #4: تأمين otps و app_settings
--
--  (أ) otps: منع anon من القراءة/الحقن المباشر — يغلق التفاف استعادة كلمة
--      المرور (قراءة رمز الضحية أو حقن رمز معروف). الدوال والـ edge function
--      تعمل بصلاحية داخلية فلا تتأثر.
--  (ب) app_settings: قراءة فقط للـ anon؛ تعديل النِسب عبر دالة أدمن موثّقة.
--
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
--  ⚠️ انشر تعديلات الكود (profile.astro + admin.astro) مع هذا معاً.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- (أ) otps — قفل الوصول المباشر
-- ---------------------------------------------------------------------
revoke all on public.otps from anon, authenticated;
-- verify_otp / reset_password (SECURITY DEFINER) + الـ edge function (service
-- role) يبقون يعملون. المتصفح لم يعد يقرأ/يكتب otps مباشرة.

-- change_phone: يتحقق من رمز أُرسل إلى بريد الحساب، ثم يغيّر رقم الجوال.
create or replace function public.change_phone(p_phone text, p_code text, p_new_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r record; v_local text; v_intl text;
  v_new_local text; v_new_intl text; v_rows int;
begin
  if p_new_phone is null or length(regexp_replace(p_new_phone,'\D','','g')) < 10 then
    raise exception 'bad_phone';
  end if;
  v_new_local := case when p_new_phone like '+20%' then '0'||substr(p_new_phone,4) else p_new_phone end;
  v_new_intl  := case when p_new_phone like '0%'   then '+2'||p_new_phone           else p_new_phone end;

  -- الرقم الجديد يجب أن يكون غير مستخدم
  if exists (select 1 from public.accounts where phone in (v_new_local, v_new_intl)) then
    raise exception 'phone_taken';
  end if;

  -- تحقق من الرمز (لأي صيغة للرقم الحالي)
  select * into r from public.otps
   where code = p_code and used = false and expires_at > now()
     and phone in (p_phone,
                   case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end,
                   case when p_phone like '0%'   then '+2'||p_phone           else p_phone end)
   order by created_at desc limit 1;
  if not found then return false; end if;
  update public.otps set used = true where id = r.id;

  v_local := case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end;
  v_intl  := case when p_phone like '0%'   then '+2'||p_phone           else p_phone end;
  update public.accounts set phone = v_new_local where phone in (v_local, v_intl);
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.change_phone(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- (ب) app_settings — قراءة فقط للـ anon؛ التعديل عبر دالة أدمن موثّقة
-- ---------------------------------------------------------------------
alter table public.app_settings enable row level security;

drop policy if exists app_settings_anon_read on public.app_settings;
create policy app_settings_anon_read on public.app_settings
  for select to anon, authenticated using (true);

revoke insert, update, delete on public.app_settings from anon, authenticated;

create or replace function public.admin_set_setting(
  p_admin_phone text, p_admin_password text, p_key text, p_value text
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

  insert into public.app_settings (key, value, updated_at)
  values (p_key, p_value, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return true;
end;
$$;
grant execute on function public.admin_set_setting(text, text, text, text) to anon, authenticated;

-- =====================================================================
--  اختبار (يجب أن يفشل عبر anon):
--   GET /rest/v1/otps?select=code   → permission denied
--   POST /rest/v1/otps {...}        → permission denied
--   PATCH /rest/v1/app_settings     → denied
-- =====================================================================
