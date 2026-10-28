-- =====================================================================
--  وصّلها — Security #139: تنظيف نسخ قديمة متروكة من دوال الحملات
--
--  نفس نمط security-138: admin_create_campaign و
--  admin_create_email_campaign كل واحدة منهم كانت عندها 3 نسخ
--  (overloads) متراكمة — كل ميزة جديدة (p_target_phone، p_send_email،
--  p_image_url، p_extra_emails) اتضافت بـ CREATE OR REPLACE بدل تعديل
--  الـ signature الموجود، فكل إضافة خلقت دالة جديدة تمامًا بدل ما
--  تستبدل القديمة.
--
--  src/pages/admin.astro بينادي دايمًا بالمجموعة الكاملة من
--  الـ parameters (بما فيها p_target_phone لـ admin_create_campaign،
--  و p_image_url + p_extra_emails لـ admin_create_email_campaign)،
--  فمفيش استدعاء حالي بيوصل للنسخ القديمة — مش باگ شغال فعليًا، بس
--  نفس نوع المخاطرة اللي أدت لمشكلة log_vehicle_service لو حد نادى
--  بمجموعة بارامترات أقل يوم ما.
--
--  بننقل النسخ القديمة لأسماء منفصلة (مش DROP — نفس سبب security-138:
--  DROP FUNCTION بيحتاج تأكيد المستخدم اللي بيتعطل أحيانًا) ونسحب
--  صلاحية التنفيذ منها.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

do $$
begin
  if exists (
    select 1 from pg_proc p
     where p.proname = 'admin_create_campaign'
       and pg_get_function_identity_arguments(p.oid) =
           'p_admin_phone text, p_admin_password text, p_title text, p_body text, p_target_role text, p_url text, p_send_at timestamp with time zone'
  ) then
    alter function public.admin_create_campaign(text, text, text, text, text, text, timestamptz) rename to admin_create_campaign_deprecated_v1;
    revoke all on function public.admin_create_campaign_deprecated_v1(text, text, text, text, text, text, timestamptz) from anon, authenticated;
  end if;

  if exists (
    select 1 from pg_proc p
     where p.proname = 'admin_create_campaign'
       and pg_get_function_identity_arguments(p.oid) =
           'p_admin_phone text, p_admin_password text, p_title text, p_body text, p_target_role text, p_url text, p_send_at timestamp with time zone, p_send_email boolean'
  ) then
    alter function public.admin_create_campaign(text, text, text, text, text, text, timestamptz, boolean) rename to admin_create_campaign_deprecated_v2;
    revoke all on function public.admin_create_campaign_deprecated_v2(text, text, text, text, text, text, timestamptz, boolean) from anon, authenticated;
  end if;

  if exists (
    select 1 from pg_proc p
     where p.proname = 'admin_create_email_campaign'
       and pg_get_function_identity_arguments(p.oid) =
           'p_admin_phone text, p_admin_password text, p_subject text, p_body text, p_target_role text, p_send_at timestamp with time zone'
  ) then
    alter function public.admin_create_email_campaign(text, text, text, text, text, timestamptz) rename to admin_create_email_campaign_deprecated_v1;
    revoke all on function public.admin_create_email_campaign_deprecated_v1(text, text, text, text, text, timestamptz) from anon, authenticated;
  end if;

  if exists (
    select 1 from pg_proc p
     where p.proname = 'admin_create_email_campaign'
       and pg_get_function_identity_arguments(p.oid) =
           'p_admin_phone text, p_admin_password text, p_subject text, p_body text, p_target_role text, p_send_at timestamp with time zone, p_image_url text'
  ) then
    alter function public.admin_create_email_campaign(text, text, text, text, text, timestamptz, text) rename to admin_create_email_campaign_deprecated_v2;
    revoke all on function public.admin_create_email_campaign_deprecated_v2(text, text, text, text, text, timestamptz, text) from anon, authenticated;
  end if;
end $$;
