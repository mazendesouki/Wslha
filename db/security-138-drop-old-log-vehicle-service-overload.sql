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
--  الحل: نحذف النسخة القديمة (8 بارامترات) ونسيب بس النسخة الجديدة.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

drop function if exists public.log_vehicle_service(text, text, text, numeric, numeric, numeric, text, timestamptz);
