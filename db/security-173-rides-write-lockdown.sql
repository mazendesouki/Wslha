-- =====================================================================
--  وصّلها — Security #173: المرحلة التالتة والأخيرة من إصلاح
--  orders/rides/stores المفتوحة بالكامل — تأمين الكتابة على rides
--
--  نفس المشكلة اللي اتصلحت في stores (security-171) و orders
--  (security-172): rides عندها RLS policies مفتوحة بالكامل (qual=true)
--  لـ anon على كل العمليات.
--
--  أبسط الثلاثة: بحثنا في الكود كله (src/, flutter_app/) ومفيش أي
--  UPDATE أو DELETE مباشر على rides خالص إلا في src/utils/adminApi.ts
--  (ملف ميت، مش متستخدم في أي حتة — نفس الملف اللي اتكشف في
--  security-171/172). كل انتقالات حالة الرحلة (قبول عرض، وصول، اكتمال،
--  إلخ) بتعدي بالفعل من دوال RPC محمية (accept_dispatch_offer,
--  driver_update_ride_status, mark_ride_arrived, settle_ride_commission,
--  إلخ) — مش raw table write. يعني مفيش دوال جديدة مطلوبة ولا تعديل
--  عميل مطلوب، تأمين RLS بس.
--
--  الـ INSERT فضل مفتوح عمدًا (طلب رحلة جديدة من العميل).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
drop policy if exists "rides_all" on public.rides;
drop policy if exists "rides_update_all" on public.rides;
drop policy if exists "rides_delete_all" on public.rides;
revoke update, delete on public.rides from anon, authenticated;
