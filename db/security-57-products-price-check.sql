-- =====================================================================
--  وصّلها — Security #57: منع سعر/كمية سالبة لمنتجات المتاجر من قاعدة
--  البيانات نفسها (مش بس من واجهة التاجر)
--
--  الثغرة: فورم إضافة/تعديل منتج في merchant-dashboard.astro كان بيفحص
--  السعر بـ "!price" — الفحص ده بيفشل يمسك رقم سالب (زي -50) لأنه
--  truthy في JavaScript، فكان بيعدّي على طول لـ INSERT/PATCH مباشر على
--  جدول products من غير أي تحقق من السيرفر خالص. الكود اتصلح في نفس
--  الكوميت، لكن قيد على مستوى القاعدة نفسها هو الضمان الحقيقي — أي
--  طريق تاني (حتى لو مستقبلي) يوصل لنفس الجدول هيتقفل بردو.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

alter table public.products
  drop constraint if exists products_price_nonneg,
  add constraint products_price_nonneg check (price >= 0);

alter table public.products
  drop constraint if exists products_compare_at_price_nonneg,
  add constraint products_compare_at_price_nonneg check (compare_at_price is null or compare_at_price >= 0);

alter table public.products
  drop constraint if exists products_stock_quantity_nonneg,
  add constraint products_stock_quantity_nonneg check (stock_quantity is null or stock_quantity >= 0);
