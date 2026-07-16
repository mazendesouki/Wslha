-- إصلاح: "permission denied for table accounts" عند حذف حساب من لوحة الأدمن
--
-- السبب: صلاحية DELETE على جدول accounts مش ممنوحة أصلاً لـ anon/authenticated
-- على مستوى القاعدة (طبقة GRANT) — ده منفصل عن سياسات RLS اللي عملناها في
-- الأمان #7 (السياسة موجودة وصح، بس بتتفعّل بعد التحقق من GRANT، ومفيش GRANT
-- من الأساس فالطلب بيترفض قبل ما يوصل لسياسة RLS خالص).
set search_path = public, extensions;

grant delete on public.accounts to anon, authenticated;
