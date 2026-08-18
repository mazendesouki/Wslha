-- =====================================================================
--  وصّلها — Security #24: تقييمات ذكية (وسوم + بادجات موثوقية)
--
--  جدول ratings موجود بالفعل على الإنتاج (بيستخدمه rides.astro،
--  driver-dashboard.astro، track.astro مباشرة عبر REST بمفتاح anon —
--  قراءة وكتابة، من غير RLS يمنع) لكنه مش متابَع في db/*.sql خالص. الملف
--  ده إضافي بس (add column if not exists) — مش بيعيد تعريف الجدول، عشان
--  ميعملش أي تعارض مع الأعمدة الموجودة فعلاً.
--
--  العمود الجديد الوحيد: tags — الوسوم السريعة اللي بتظهر في تطبيق
--  الموبايل (مثال: "🚗 سواق مهذب"، "⏱️ وصل بسرعة") بديل/مكمّل للنجوم
--  التقليدية. باقي الميزات (بادج موثوقية السائق/العميل/المتجر، أفضل
--  الأصناف تقييمًا) بتُحسب بقراءة مباشرة من نفس الجدول، بنفس النمط
--  اللي rides.astro/driver-dashboard.astro بيستخدموه أصلاً — من غير
--  RPC جديدة.
--
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.ratings add column if not exists tags text[];

create index if not exists ratings_driver_rated_by_idx on public.ratings (driver_phone, rated_by);
create index if not exists ratings_customer_rated_by_idx on public.ratings (customer_phone, rated_by);
create index if not exists ratings_store_idx on public.ratings (store_id);
create index if not exists ratings_order_code_idx on public.ratings (order_code);
