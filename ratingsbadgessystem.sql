-- ═══════════════════════════════════════════════════════════════
-- Unified rating & badge system: bidirectional ratings (driver↔
-- customer) + a "comfort/AC vehicle" flag. Merchant ratings already
-- existed (track.astro posts store_rating/driver_rating rows into
-- this same `ratings` table after delivery) — no new table needed
-- there, the gap was only that stores.astro/store/[id].astro never
-- displayed the live numbers (fixed in code, not here).
-- Badges are computed live from these numbers (avg rating + trip
-- count) rather than stored/cached, so they always reflect the
-- latest ratings with no separate "recalculate" step needed.
-- Run once in the Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════════

-- 1) Direction flag on the existing ratings table (customer→driver was
--    the only direction until now). Existing rows default to 'customer'
--    (i.e. unchanged meaning: customer rated the driver).
alter table public.ratings add column if not exists rated_by text not null default 'customer'
  check (rated_by in ('customer', 'driver'));
create index if not exists ratings_customer_ratedby_idx on public.ratings (customer_phone, rated_by);

-- 2) Comfort/AC vehicle flag — driver self-declared.
alter table public.driver_applications add column if not exists has_ac boolean not null default false;
