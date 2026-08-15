-- ═══════════════════════════════════════════════════════════════
-- تفاصيل أوسع للمنتج: صورة، سعر قبل الخصم، الكمية المتاحة، ومواصفات
-- مرنة حسب نوع المتجر (مقاس/لون للملابس، نوع العدسة للنظارات، الوحدة
-- للسوبر ماركت والخضار والفاكهة...). Run this whole file once in the
-- Supabase SQL Editor. Idempotent.
-- ═══════════════════════════════════════════════════════════════

alter table public.products
  add column if not exists image_url        text,
  add column if not exists compare_at_price  numeric,
  add column if not exists stock_quantity    integer,
  add column if not exists attributes        jsonb not null default '{}'::jsonb;

comment on column public.products.image_url is 'رابط صورة المنتج (Supabase Storage, دلو product-images)';
comment on column public.products.compare_at_price is 'السعر قبل الخصم — يُعرض مشطوباً فوق السعر الحالي إن كان أكبر من price';
comment on column public.products.stock_quantity is 'الكمية المتاحة، NULL = غير محدودة';
comment on column public.products.attributes is 'مواصفات مرنة حسب نوع المتجر: {"size":"L","color":"أحمر"} إلخ';

-- ---------------------------------------------------------------------
-- دلو تخزين صور المنتجات (نفس نمط 'documents' و 'marketplace')
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

drop policy if exists "public read product-images" on storage.objects;
create policy "public read product-images" on storage.objects
  for select using (bucket_id = 'product-images');

drop policy if exists "anon upload product-images" on storage.objects;
create policy "anon upload product-images" on storage.objects
  for insert to anon, authenticated with check (bucket_id = 'product-images');
