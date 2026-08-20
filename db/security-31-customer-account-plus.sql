-- =====================================================================
--  وصّلها — تحسين شاشة "حسابي" في تطبيق العميل: عناوين محفوظة
--
--  الأقسام التانية اللي اتضافت لشاشة حسابي (إحصائيات الطلبات، الصورة
--  الشخصية، سجل التقييمات) بتستخدم جداول/أعمدة موجودة بالفعل
--  (orders/rides عبر OrdersRepository.fetchHistory، accounts.avatar_url
--  من security-28، جدول ratings) — من غير أي تعديل على قاعدة البيانات.
--  العنصر الوحيد الجديد فعليًا هو جدول عناوين العميل المحفوظة.
--
--  نفس نموذج الثقة المستخدم في باقي الجداول (ratings، orders، rides):
--  مفتاح anon بيبعت رقم الهاتف من الجلسة المحفوظة على الجهاز، من غير
--  Supabase Auth حقيقي — فمفيش طريقة لفرض ownership فعلي على مستوى
--  RLS، فسياسات anon هنا "true" بنفس مستوى الثقة الموجود فعلاً على
--  ratings_insert_all/ratings_select_all (security-26).
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.saved_addresses (
  id uuid primary key default gen_random_uuid(),
  customer_phone text not null,
  label text not null default 'المنزل',
  area text,
  address text not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists saved_addresses_phone_idx on public.saved_addresses (customer_phone);

alter table public.saved_addresses enable row level security;

drop policy if exists saved_addresses_select on public.saved_addresses;
create policy saved_addresses_select on public.saved_addresses
  for select to anon, authenticated using (true);

drop policy if exists saved_addresses_insert on public.saved_addresses;
create policy saved_addresses_insert on public.saved_addresses
  for insert to anon, authenticated with check (true);

drop policy if exists saved_addresses_update on public.saved_addresses;
create policy saved_addresses_update on public.saved_addresses
  for update to anon, authenticated using (true) with check (true);

drop policy if exists saved_addresses_delete on public.saved_addresses;
create policy saved_addresses_delete on public.saved_addresses
  for delete to anon, authenticated using (true);
