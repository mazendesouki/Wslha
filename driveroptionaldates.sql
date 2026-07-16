-- =====================================================================
--  وصّلها — السماح بترك تاريخي انتهاء التأمين والفحص فاضيين (اختياريين)
--
--  الواجهة مصممة أصلاً على إن التأمين والفحص اختياريين (لو دخلت تاريخ
--  لازم يكون صالح، لكن مسموح تسيبهم فاضيين) — لكن العمودين في قاعدة
--  البيانات كانوا NOT NULL، فأي طلب سايب الحقلين دول فاضيين كان بيترفض
--  برسالة "null value ... violates not-null constraint".
--
--  شغّله مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.driver_applications alter column insurance_expiry  drop not null;
alter table public.driver_applications alter column inspection_expiry drop not null;
