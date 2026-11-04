-- =====================================================================
--  وصّلها — Security #159: تحصين _check_admin مركزيًا ضد محاولات تخمين
--  غير محدودة (Phase 1 من إصلاح ثغرة كلمة مرور المشرف — متابعة
--  security-158)
--
--  56 دالة أدمن بتتحقق من كلمة المرور كل واحدة لوحدها inline، من غير
--  أي حد لعدد المحاولات. security-158 أصلح واحدة بس (الأهم: سحب
--  الأرباح). الإصلاح الشامل: _check_admin() دالة مشتركة موجودة بالفعل
--  (بترجع boolean بس، بتتستخدم من 3 دوال فقط حاليًا) — بنضيف لها منطق
--  القفل (نفس جدول login_attempts اللي security-156/157/158 بيستخدموه،
--  بالـ admin_phone)، وبعد كده كل دالة تتحوّل تستدعيها بدل ما تعمل
--  الفحص بنفسها. أي دالة بتستخدم _check_admin() وبترجع false/تعمل
--  return عادي (مش raise) عند فشل الدخول، الإصلاح ليها آمن 100% ومفيش
--  أي تغيير في السلوك الخارجي — نفس نقطة الضعف اللي security-158
--  اكتشفها (exception بتلغي الـ insert) مش موجودة هنا لأن مفيش raise.
--
--  الدوال اللي بتعمل raise عند فشل الدخول (10 دوال) محتاجة تعديل
--  منفصل زي admin_withdraw_platform_profit بالظبط — هيتعملوا في
--  migration تانية لأن كل واحدة شكلها مختلف (نوع الإرجاع مختلف) ومحتاجة
--  تحديث في admin.astro كمان.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public._check_admin(p_admin_phone text, p_admin_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_admin        record;
  v_key          text := case when p_admin_phone like '+2%' then substr(p_admin_phone, 3) else p_admin_phone end;
  v_locked_until timestamptz;
  v_prev_count   int;
  v_new_count    int;
begin
  select la.locked_until into v_locked_until
    from public.login_attempts la where la.phone = v_key;
  if v_locked_until is not null and v_locked_until > now() then
    return false;
  end if;

  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  if v_admin.phone is null or v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
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
    return false;
  end if;

  delete from public.login_attempts where phone = v_key;
  return true;
end;
$$;
