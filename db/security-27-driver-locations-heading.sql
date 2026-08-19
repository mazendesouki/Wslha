-- =====================================================================
--  وصّلها — إضافة عمود heading الناقص من جدول driver_locations
--
--  الجدول ده كان متعرّف في supabase-schema.sql بعمود heading من الأول،
--  بس الملف بيستخدم "CREATE TABLE IF NOT EXISTS" — يعني لو الجدول
--  اتعمل قبل ما العمود ده يتضاف للملف، محدش رجع عدّله. ظهر الخطأ ده فعليًا
--  وقت اختبار الخريطة الحية: PostgrestException "Could not find the
--  'heading' column of 'driver_locations' in the schema cache" — وهو
--  سبب فشل DriverRepository.pingLocation() (بيانات موقع السائق واتجاهه
--  على الخريطة الحية بتفشل تبعت بالكامل).
--
--  آمن لإعادة التشغيل. شغّله كامل مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

alter table public.driver_locations
  add column if not exists heading double precision default 0;

-- يجبر PostgREST يعيد تحميل الـ schema cache فورًا بدل ما يستنى دورته
-- الدورية العادية.
notify pgrst, 'reload schema';
