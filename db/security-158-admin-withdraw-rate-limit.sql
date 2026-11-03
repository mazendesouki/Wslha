-- =====================================================================
--  وصّلها — Security #158: تحصين admin_withdraw_platform_profit ضد
--  محاولات تخمين غير محدودة (Phase 0 من إصلاح ثغرة أوسع)
--
--  اتكشف وقت فحص إضافي بعد قائمة فحص الأمان: 57 دالة أدمن (admin_*)
--  بتتحقق من كلمة مرور المشرف مباشرة جوه كل دالة، من غير أي حد لعدد
--  المحاولات — وكلهم متاحين لـ anon (المفتاح العام). حساب الأدمن
--  بيتحكم في كل حاجة، فده خطر حقيقي. إصلاح الـ57 دالة كلها شغل كبير
--  محتاج مراجعة منفصلة؛ الأولوية دلوقتي: admin_withdraw_platform_profit
--  (الدالة اللي بتحرّك فلوس حقيقية فعليًا).
--
--  ملحوظة مهمة اتكشفت أثناء الاختبار الحي: أول نسخة من الإصلاح كانت
--  بتسجّل المحاولة الفاشلة في login_attempts ثم تعمل raise exception
--  بنفس الاستدعاء — لكن في Postgres أي exception غير ملتقطة بتلغي
--  (rollback) كل حاجة اتعملت في نفس المعاملة، بما فيها الـ insert اللي
--  اتعمل قبلها بسطرين. يعني العداد كان هيفضل صفر دايمًا مهما عدد
--  المحاولات، والقفل مكنش هيشتغل خالص في الاستخدام الحقيقي — إصلاح
--  شكلي بس من غير أي حماية فعلية. الحل الصحيح: الدالة بترجّع
--  jsonb{ok:false, error, message} بدل ما تعمل raise على الحالات
--  التلاتة اللي بتحتاج تسجيل محاولة (قفل سابق / مفتاح أمان غلط / كلمة
--  مرور غلط) — عشان الـ insert يتثبّت فعليًا كجزء من معاملة ناجحة.
--  باقي التحققات (مبلغ غير صالح، رصيد غير كافي) فضلت زي ما هي
--  (raise exception) لأنها مش جزء من مسار منع التخمين وما قبلهاش أي
--  insert محتاج يتحمي.
--
--  العميل (admin.astro) اتعدّل ليقرا result.ok بدل ما يعتمد على
--  catch(e) بس.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.admin_withdraw_platform_profit(
  p_admin_phone text, p_admin_password text, p_action_key text,
  p_amount numeric, p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_admin        record;
  v_balance      numeric;
  v_id           text;
  v_key          text := case when p_admin_phone like '+2%' then substr(p_admin_phone, 3) else p_admin_phone end;
  v_locked_until timestamptz;
  v_prev_count   int;
  v_new_count    int;
begin
  select la.locked_until into v_locked_until
    from public.login_attempts la where la.phone = v_key;
  if v_locked_until is not null and v_locked_until > now() then
    return jsonb_build_object('ok', false, 'error', 'rate_limited', 'message', 'محاولات كتير غلط — حاول تاني بعد شوية');
  end if;

  if not public.verify_action_key(p_action_key) then
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
    return jsonb_build_object('ok', false, 'error', 'invalid_action_key', 'message', 'مفتاح الأمان غير صحيح');
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
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials', 'message', 'كلمة مرور المشرف غير صحيحة');
  end if;

  delete from public.login_attempts where phone = v_key;

  if p_amount is null or p_amount <= 0 then
    raise exception 'المبلغ غير صالح';
  end if;

  select coalesce(sum(case when type = 'commission' then amount when type = 'withdrawal' then amount else 0 end), 0)
    into v_balance
    from public.wallet_transactions where phone = 'platform' and type in ('commission', 'withdrawal');

  if p_amount > v_balance then
    raise exception 'المبلغ المطلوب أكبر من الرصيد المتاح (%.2f ج.م)', v_balance;
  end if;

  v_id := 'plat-wd-' || extract(epoch from clock_timestamp())::bigint || '-' || substr(md5(random()::text), 1, 6);

  perform public.add_wallet_balance('platform', -p_amount);

  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values (v_id, 'platform', -p_amount, 'withdrawal', coalesce(p_note, 'سحب أرباح المنصة — ' || v_admin.name), now());

  insert into public.platform_withdrawals (id, admin_phone, admin_name, amount, note, balance_before, balance_after)
  values (v_id, v_admin.phone, v_admin.name, p_amount, p_note, v_balance, v_balance - p_amount);

  -- بث لحظي فاضٍ (بدون مبالغ ولا بيانات شخصية) — security-155.
  perform realtime.send(jsonb_build_object('source', 'withdrawal'), 'update', 'platform-finance', false);

  return jsonb_build_object('ok', true, 'balance_after', v_balance - p_amount);
end;
$$;
grant execute on function public.admin_withdraw_platform_profit(text, text, text, numeric, text) to anon, authenticated;
