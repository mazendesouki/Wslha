-- =====================================================================
--  وصّلها — Security #52: بنية تحتية للتحقق من مستندات تسجيل السائق
--
--  الهدف (بناءً على طلب صريح): منع تكرار نفس صورة المستند لأكتر من
--  حساب، ومراجعة صور المستندات الرسمية (رخصة قيادة/استمارة/تأمين/فحص/
--  بطاقة رقم قومي/شهادة حسن سيرة) عشان تكون فعلاً صور حقيقية للمستند
--  المطلوب مش صور عشوائية — عبر Claude Vision من src/pages/api/
--  documents/verify.ts (سيرفر-سايد، Anthropic API).
--
--  الجدول ده بس بصمات الصور (sha256 hash) — مش الصور نفسها ولا أي
--  بيانات شخصية. لا وصول مباشر من anon/authenticated خالص، الكتابة/
--  القراءة بس من الـ API route عبر service role key.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.document_image_hashes (
  id          uuid primary key default gen_random_uuid(),
  phone       text not null,
  doc_type    text not null,
  image_hash  text not null,
  created_at  timestamptz not null default now()
);

create index if not exists document_image_hashes_hash_idx  on public.document_image_hashes (image_hash);
create index if not exists document_image_hashes_phone_idx on public.document_image_hashes (phone);

alter table public.document_image_hashes enable row level security;
revoke all on public.document_image_hashes from anon, authenticated;
