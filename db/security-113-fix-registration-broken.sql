-- =====================================================================
--  وصّلها — Security #113: إصلاح عاجل — تسجيل عملاء جدد متعطل بالكامل
--
--  اكتُشف بالصدفة أثناء اختبار ضغط للتسجيل (مش جزء من الاختبار نفسه):
--  أي محاولة INSERT جديدة على public.accounts (يعني أي تسجيل حساب
--  جديد — عميل/سائق/تاجر) كانت بترجع:
--
--    ERROR: 42501: permission denied for table accounts
--    HINT: Grant the required privileges to the current role with:
--          GRANT SELECT ON public.accounts TO anon;
--    CONTEXT: PL/pgSQL function generate_referral_code()
--
--  السبب: trigger `trg_set_referral_code` (security-69) بينادي
--  set_referral_code_on_insert() اللي بتنادي generate_referral_code() —
--  والدالتين دول من غير SECURITY DEFINER، يعني بيشتغلوا بصلاحيات
--  الـ role المستدعي (anon) مش صاحب الدالة. generate_referral_code()
--  بتعمل SELECT من accounts (للتأكد إن الكود مش مكرر) — وصلاحية
--  SELECT على accounts اتشالت من anon في تحصين أمني لاحق (security-06/16،
--  قبل ما حد يراجع إن الـ trigger ده هيتأثر). النتيجة: أي تسجيل جديد
--  من التطبيق أو الموقع كان بيفشل بصمت تام من ساعة ما السحب ده اتطبّق.
--
--  تم التأكد المباشر من الخطأ بمحاكاة INSERT بصلاحيات anon (SET ROLE
--  anon) قبل كتابة الإصلاح ده.
--
--  الإصلاح: إضافة SECURITY DEFINER + search_path للدالتين، زي باقي كل
--  دالة في المشروع بتحتاج تتخطى قيود الصلاحيات دي — من غير أي تغيير
--  لمنطقهم.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.generate_referral_code()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_code text;
begin
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.accounts where referral_code = v_code);
  end loop;
  return v_code;
end;
$$;

create or replace function public.set_referral_code_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.referral_code is null then
    new.referral_code := public.generate_referral_code();
  end if;
  return new;
end;
$$;
