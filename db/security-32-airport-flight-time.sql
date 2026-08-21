-- =====================================================================
--  وصّلها — تخزين موعد الرحلة الفعلي لتوصيل المطار
--
--  airport.astro/airport_screen.dart كانا بيحطوا وقت الرحلة (والاتجاه/نوع
--  الرحلة) كنص جوّه عمود notes بس — يعني أي حساب لاحق (عدّاد تنازلي،
--  تذكير قبل الرحلة، عرضها تاني بعد إعادة فتح التطبيق) كان محتاج يفكّك
--  نص notes، وده هش وغير موثوق. الأعمدة دي بتخزنهم كقيم حقيقية بدل كده.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

alter table public.rides add column if not exists flight_time timestamptz;
alter table public.rides add column if not exists airport_direction text; -- departure | arrival
alter table public.rides add column if not exists airport_trip_type text; -- international | domestic
