-- =====================================================================
--  وصّلها — Security #50: بنية تحتية لإدارة الجلسات (Refresh Token Rotation)
--
--  هذا الملف بس البنية التحتية (جدول الجلسات + دالة التنظيف) لنظام
--  Logout/Session Management الجديد المبني على Refresh Token Rotation —
--  الـ endpoints نفسها (login/refresh/logout) في src/pages/api/auth/*.ts
--  (Astro API routes سيرفر-سايد على Vercel، الوحيدة اللي تقدر تحط
--  HttpOnly cookie).
--
--  ملاحظة مهمة (اتفقنا عليها صراحة): النظام ده بنية تحتية قائمة بذاتها
--  دلوقتي — لسه مش مربوط ببقية دوال المشروع (كل RPC زي
--  accept_dispatch_offer/settle_order_commission لسه بتاخد رقم الهاتف
--  كبارامتر وتثق فيه مباشرة، زي ما هي). ربط كل المشروع بالجلسات دي
--  تغيير معماري أكبر ومخاطرة، مقصود إنه يتعمل تدريجيًا بعد كده.
--
--  التصميم:
--   • access token: JWT قصير العمر (15 دقيقة) — بيتوقّع/يتحقّق منه في
--     كود الـ API route نفسه (HS256)، مش محتاج صف في الداتابيز.
--   • refresh token: قيمة عشوائية، بيتخزن في auth_sessions بس الـ hash
--     بتاعها (sha256) — مش القيمة الخام أبدًا. كل عملية refresh بتعمل
--     rotation: تولّد refresh token جديد، تحط القديم status='rotated'
--     مع grace_expires_at = now()+5s (فترة سماح لتضارب الطلبات
--     المتزامنة)، وتربطهم بـ replaced_by.
--   • family_id: كل تسجيل دخول = family جديدة. أي محاولة استخدام توكن
--     status='revoked' أو 'rotated' بعد انتهاء فترة السماح = هجوم
--     محتمل (إعادة استخدام توكن مسروق) → تُلغى العائلة كلها فورًا
--     ويتسجّل تنبيه أمني في security_alerts.
--   • absolute_expires_at: ثابت لكل العائلة من أول تسجيل دخول (30 يوم)
--     — مايتجددش مع كل rotation، عشان الجلسة تنتهي فعليًا بعد شهر مهما
--     كان المستخدم نشط.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.auth_sessions (
  id                   uuid primary key default gen_random_uuid(),
  family_id            uuid not null,
  account_phone        text not null,
  token_hash           text not null,
  status               text not null default 'active' check (status in ('active', 'rotated', 'revoked')),
  replaced_by          uuid references public.auth_sessions(id),
  issued_at            timestamptz not null default now(),
  grace_expires_at     timestamptz,
  absolute_expires_at  timestamptz not null,
  ip                   text,
  user_agent           text,
  revoked_at           timestamptz,
  revoked_reason       text
);

create unique index if not exists auth_sessions_token_hash_idx on public.auth_sessions (token_hash);
create index if not exists auth_sessions_family_idx  on public.auth_sessions (family_id);
create index if not exists auth_sessions_phone_idx   on public.auth_sessions (account_phone);
create index if not exists auth_sessions_gc_idx      on public.auth_sessions (status, absolute_expires_at);

-- Security alerts — audit trail for detected refresh-token reuse (the
-- "استخدام توكن ملغى بعد الغريس بيريود = هجوم" case). This table is the
-- durable record; src/pages/api/auth/refresh.ts additionally makes a
-- best-effort call to the existing send-push edge function so the user
-- gets a real notification, but that call is best-effort/non-blocking —
-- this row is written first and is never lost even if the push fails.
create table if not exists public.security_alerts (
  id            uuid primary key default gen_random_uuid(),
  account_phone text not null,
  family_id     uuid,
  kind          text not null,
  detail        jsonb,
  created_at    timestamptz not null default now(),
  acknowledged  boolean not null default false
);
create index if not exists security_alerts_phone_idx on public.security_alerts (account_phone);

-- No anon/authenticated access at all — every access path to this table
-- is server-side only, either the Vercel API routes (service-role key,
-- which bypasses RLS/grants entirely) or this cleanup function.
alter table public.auth_sessions   enable row level security;
alter table public.security_alerts enable row level security;
revoke all on public.auth_sessions   from anon, authenticated;
revoke all on public.security_alerts from anon, authenticated;

-- ---------------------------------------------------------------------
-- Garbage collection — deletes rows that can no longer matter: past
-- their absolute 30-day ceiling, or revoked/rotated more than a day ago
-- (kept briefly after that so a delayed duplicate request can still be
-- correctly identified as reuse instead of "token_not_found").
-- Schedule this to run daily — see the note at the bottom of the file
-- for how, since it depends on what's enabled on this Supabase project.
-- ---------------------------------------------------------------------
create or replace function public.cleanup_expired_sessions()
returns int
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_deleted int;
begin
  delete from public.auth_sessions
   where absolute_expires_at < now()
      or (status <> 'active' and coalesce(revoked_at, issued_at) < now() - interval '1 day');
  get diagnostics v_deleted = row_count;

  delete from public.security_alerts where created_at < now() - interval '90 days';

  return v_deleted;
end;
$$;
revoke all on function public.cleanup_expired_sessions() from public, anon, authenticated;

-- =====================================================================
--  جدولة يومية للتنظيف (Cron Job) — اختَر واحدة حسب اللي متاح عندك:
--
--  الخيار أ (لو pg_cron مفعّل في المشروع — Database → Extensions):
--    select cron.schedule('cleanup-expired-sessions', '0 3 * * *',
--      'select public.cleanup_expired_sessions();');
--
--  الخيار ب (لو pg_cron مش مفعّل — الافتراضي على أغلب مشاريع Supabase
--  المجانية): استخدم GitHub Actions scheduled workflow (زي باقي أتمتة
--  المشروع ده) يستدعي الدالة عبر RPC بمفتاح service_role مرة يوميًا —
--  ملف جاهز: .github/workflows/cleanup-sessions.yml (في نفس الكوميت).
-- =====================================================================
