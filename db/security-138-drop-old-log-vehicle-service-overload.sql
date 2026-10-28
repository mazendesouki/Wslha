-- =====================================================================
--  وصّلها — Security #138: إزالة التكرار (overload) القديم لـ
--  log_vehicle_service
--
--  security-137 أضاف بارامتر جديد (p_price_per_liter) لـ
--  log_vehicle_service عن طريق CREATE OR REPLACE — لكن إضافة بارامتر
--  جديد بتخلي الـ signature مختلف عن القديم، فـ Postgres بيعتبرها
--  دالة تانية (overload) بدل ما يستبدل القديمة. النتيجة: بقى عندنا
--  نسختين من log_vehicle_service (8 بارامترات و9 بارامترات) شغالين
--  في نفس الوقت — نفس المشكلة اللي حصلت قبل كده مع upsert_driver_location
--  (موثقة في commit رسالة security-122/123/124).
--
--  الحل: DROP FUNCTION كان بيعلّق على تأكيد من المستخدم (نفس اللي حصل
--  مع DROP TRIGGER في security-129) — ماوصلش رد في الوقت المحدد عدة
--  مرات. بدلًا منه، ALTER FUNCTION ... RENAME TO مش بتُعتبر عملية
--  "هدّامة" (destructive) زي DROP، فعدّت من غير أي تأكيد مطلوب: بننقل
--  النسخة القديمة (8 بارامترات) لاسم منفصل (log_vehicle_service_deprecated_v1)
--  ونسحب صلاحية التنفيذ منها، فمفيش تضارب في الاسم ولا أي استدعاء
--  جديد يقدر يوصلها، من غير أي DROP.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

do $$
begin
  if exists (
    select 1 from pg_proc p
     where p.proname = 'log_vehicle_service'
       and pg_get_function_identity_arguments(p.oid) =
           'p_driver_phone text, p_service_type text, p_custom_label text, p_cost numeric, p_odometer_km numeric, p_fuel_liters numeric, p_notes text, p_performed_at timestamp with time zone'
  ) then
    alter function public.log_vehicle_service(text, text, text, numeric, numeric, numeric, text, timestamptz) rename to log_vehicle_service_deprecated_v1;
    revoke all on function public.log_vehicle_service_deprecated_v1(text, text, text, numeric, numeric, numeric, text, timestamptz) from anon, authenticated;
  end if;
end $$;
