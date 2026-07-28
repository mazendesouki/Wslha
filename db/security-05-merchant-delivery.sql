-- =====================================================================
--  وصّلها — Security #5: خدمة توصيل التاجر (Merchant-initiated delivery)
--
--  التاجر بيدخل بيانات عميل (اسم/تليفون/منتجات) ويطلب توصيل بينه وبين
--  المتجر — في أي اتجاه (بيع عادي، أو استرجاع من العميل). الطلب بيتسجّل
--  في جدول orders الموجود بالفعل (نفس الجدول اللي بيستخدمه courier.astro)
--  عشان يستفيد من نفس محرك التوزيع (server/index.js) بدون أي تعديل فيه —
--  فقط أعمدة جديدة لتمييز النوع وحفظ رسوم الخدمة الثابتة.
--
--  Run once in the Supabase SQL Editor. Idempotent — safe to re-run.
-- =====================================================================
set search_path = public, extensions;

alter table public.orders add column if not exists source text;
alter table public.orders add column if not exists direction text
  check (direction in ('store_to_customer', 'customer_to_store'))
  default 'store_to_customer';
alter table public.orders add column if not exists service_fee numeric default 0;

create index if not exists orders_source_idx on public.orders(source);

-- رسوم خدمة التطبيق الثابتة لكل طلب توصيل تاجر — قابلة للتعديل من لوحة
-- الأدمن (نفس نمط commission_delivery) بدون الحاجة لإعادة نشر الكود.
insert into public.app_settings (key, value)
values ('merchant_delivery_service_fee', '10')
on conflict (key) do nothing;
