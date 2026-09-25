-- ═══════════════════════════════════════════════════════════════
-- سوق المستعمل شحنة-نوع availability check (security-94's shipment_type
-- selector, requested live follow-up): each shipment-type chip should
-- reflect whether a driver with the matching REGISTERED vehicle_category
-- (driver_applications.vehicle_category — sedan/suv/van/motorcycle/cargo,
-- see driver.astro's v-cat select) is actually online right now, not an
-- arbitrary label. Mirrors get_available_drivers_count's (security-91)
-- online/idle/fresh criteria, narrowed to one category — same narrow-RPC
-- pattern (count only, no raw row exposure).
--
-- Joins each driver_locations row to their LATEST approved
-- driver_applications row per phone (DISTINCT ON) — a driver who
-- re-applied after changing vehicle only counts under their current
-- category, not a stale one from an earlier application.
--
-- 'flatbed' (سيارة سطحة — car-carrier, for the "سيارة" shipment option)
-- isn't a category any driver can currently register as (not in
-- driver.astro's v-cat select), so it always returns 0 until that's
-- added — intentional, matches the "غير متوفر الآن" case as specified.
-- ═══════════════════════════════════════════════════════════════

create or replace function public.get_available_drivers_count_by_category(p_vehicle_category text)
returns integer
language sql
stable
security definer
set search_path = public, extensions
as $$
  select count(*)::integer
  from public.driver_locations dl
  join (
    select distinct on (phone) phone, vehicle_category
    from public.driver_applications
    where status = 'approved'
    order by phone, created_at desc
  ) da on da.phone = dl.driver_phone
  where dl.is_online = true
    and dl.ride_id is null
    and dl.current_order_id is null
    and dl.updated_at > now() - interval '10 minutes'
    and da.vehicle_category = p_vehicle_category;
$$;
grant execute on function public.get_available_drivers_count_by_category(text) to anon, authenticated;
