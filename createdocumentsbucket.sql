-- =====================================================================
--  وصّلها — إنشاء bucket التخزين "documents" (كان غير موجود أصلاً)
--
--  كل رفع مستندات في الموقع (صور السائقين، الهويات، الرخص، صور
--  السيارات...) بيحاول يترفع لـ storage bucket اسمه "documents" —
--  لكنه لم يكن منشأ في المشروع، فكل رابط صورة كان بيرجع
--  "Bucket not found" لأي حد يحاول يفتحه (زي الأدمن وقت المراجعة).
--
--  شغّله مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- 1) إنشاء الـ bucket — public عشان روابط الصور تشتغل بدون توثيق إضافي
insert into storage.buckets (id, name, public)
values ('documents', 'documents', true)
on conflict (id) do update set public = true;

-- 2) صلاحيات القراءة العامة (لازمة عشان لوحة الأدمن تقدر تعرض الصور)
drop policy if exists "public read documents" on storage.objects;
create policy "public read documents" on storage.objects
  for select using (bucket_id = 'documents');

-- 3) صلاحية الرفع لأي مستخدم (نفس نمط باقي الموقع — anon key بيرفع مباشرة)
drop policy if exists "anon upload documents" on storage.objects;
create policy "anon upload documents" on storage.objects
  for insert to anon, authenticated with check (bucket_id = 'documents');
