-- =====================================================================
--  وصّلها — Security #172: المرحلة الثانية من إصلاح orders/rides/stores
--  المفتوحة بالكامل — تأمين الكتابة على orders
--
--  نفس المشكلة اللي اتصلحت في stores (security-171): orders عندها RLS
--  policies مفتوحة بالكامل (qual=true) لـ anon على كل العمليات.
--
--  الفرق هنا: مفيش دوال جديدة مطلوبة! الدوال المحمية
--  (merchant_accept_order / merchant_reject_order / merchant_mark_order_
--  ready) موجودة بالفعل من security-48 وبتتحقق إن stores.owner_phone
--  فعلاً بتاع صاحب الطلب — كانت بس مستخدمة في merchant-dashboard.astro،
--  و restaurant-orders.astro كان لسه بيعمل raw PATCH على orders مباشرة
--  من غير أي تحقق ملكية خالص (اتصلح في نفس الوقت مع المigration دي).
--
--  الـ INSERT فضل مفتوح عمدًا (تسجيل طلب جديد من العميل — نفس منطق
--  stores، مفيش بيانات موجودة ممكن تتبهدل).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
drop policy if exists "anon all orders" on public.orders;
drop policy if exists "orders_update_all" on public.orders;
drop policy if exists "orders_delete_all" on public.orders;
revoke update, delete on public.orders from anon, authenticated;
