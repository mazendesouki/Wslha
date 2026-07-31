-- =====================================================================
--  وصّلها — Security #8: عمود "سيارتي نظيفة" في طلب انضمام السائق
--
--  driver.astro already had a self-declared "❄️ سيارتي مكيفة" (has_ac)
--  checkbox — this adds the matching "🧼 سيارتي نظيفة" one so the
--  customer-facing driver card (Flutter + web) can show both badges.
--
--  Run this whole file once in the Supabase SQL Editor. Idempotent.
-- =====================================================================

set search_path = public, extensions;

alter table public.driver_applications
  add column if not exists is_clean boolean not null default false;
