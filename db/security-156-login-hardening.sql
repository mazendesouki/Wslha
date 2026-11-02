-- =====================================================================
--  وصّلها — Security #156: تحصين verify_login
--
--  اتكشف وقت مراجعة قائمة فحص الأمان قبل الإطلاق:
--
--  1) verify_login (security-01) فيه مقارنة احتياطية بنص صريح
--     (`or a.password = p_password`) كانت ضرورية مؤقتًا وقت أول نقل
--     لكلمات المرور من نص صريح لـ bcrypt، عشان محدش يتقفل بره حسابه.
--     دلوقتي: trigger (trg_hash_account_password) بيشفّر أي كلمة مرور
--     بتتكتب من زمان، واتأكدنا مباشرة من البيانات الحية إن 0 من أصل 9
--     حسابات لسه فيها كلمة مرور مش bcrypt. المقارنة الاحتياطية بقت
--     مخاطرة دايمة من غير أي فايدة فعلية — لو أي كود تاني (bug أو
--     migration غلط) كتب كلمة مرور صريحة يوم من الأيام، هتشتغل كمقارنة
--     صحيحة من غير تنبيه. اتشالت، وبقى الاعتماد بس على bcrypt.
--
--  2) مفيش أي rate limiting على محاولات تسجيل الدخول خالص (تعليق
--     security-01 نفسه بيقول كده صراحة: "so there is no login-lockout
--     window"). ده بيسمح بمحاولات تخمين كلمة مرور غير محدودة. الحل:
--     جدول login_attempts بسيط — بعد 5 محاولات غلط خلال 15 دقيقة،
--     الحساب (برقم التليفون) بيتقفل 15 دقيقة. العداد بيتصفّر تلقائيًا
--     لو آخر محاولة كانت أقدم من 15 دقيقة، وبيتمسح تمامًا بعد أي دخول
--     ناجح. الجدول مقفول تمامًا على anon/authenticated (بيتقرا/يتكتب
--     بس من جوه verify_login بصلاحية SECURITY DEFINER).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.login_attempts (
  phone           text primary key,
  fail_count      int not null default 0,
  last_attempt_at timestamptz not null default now(),
  locked_until    timestamptz
);
revoke all on public.login_attempts from anon, authenticated;

create or replace function public.verify_login(p_phone text, p_password text)
returns table (
  phone text, name text, username text, email text,
  role text, status text, city text, created_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_key          text := case when p_phone like '+2%' then substr(p_phone, 3) else p_phone end;
  v_locked_until timestamptz;
  v_ok           boolean;
  v_prev_count   int;
  v_new_count    int;
begin
  select la.locked_until into v_locked_until
    from public.login_attempts la where la.phone = v_key;
  if v_locked_until is not null and v_locked_until > now() then
    raise exception 'محاولات دخول كتير غلط — حاول تاني بعد شوية' using errcode = '28000';
  end if;

  select exists(
    select 1 from public.accounts a
     where (a.phone = p_phone
         or a.phone = case when p_phone like '+2%' then substr(p_phone, 3) else '+2' || p_phone end)
       and a.password = extensions.crypt(p_password, a.password)
  ) into v_ok;

  if not v_ok then
    select la.fail_count into v_prev_count
      from public.login_attempts la
     where la.phone = v_key and la.last_attempt_at > now() - interval '15 minutes';
    v_new_count := coalesce(v_prev_count, 0) + 1;

    insert into public.login_attempts (phone, fail_count, last_attempt_at, locked_until)
    values (v_key, v_new_count, now(), case when v_new_count >= 5 then now() + interval '15 minutes' else null end)
    on conflict (phone) do update
      set fail_count = excluded.fail_count,
          last_attempt_at = excluded.last_attempt_at,
          locked_until = excluded.locked_until;
    return;
  end if;

  delete from public.login_attempts where phone = v_key;

  return query
    select a.phone, a.name, a.username, a.email, a.role, a.status, a.city, a.created_at
      from public.accounts a
     where (a.phone = p_phone
         or a.phone = case when p_phone like '+2%' then substr(p_phone, 3) else '+2' || p_phone end)
       and a.password = extensions.crypt(p_password, a.password)
     limit 1;
end;
$$;
grant execute on function public.verify_login(text, text) to anon;
