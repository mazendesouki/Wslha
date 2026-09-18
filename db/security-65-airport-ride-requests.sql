-- ═══════════════════════════════════════════════════════════════
-- Airport rides as a persistent driver-side request list, separate
-- from the timed dispatch_offers pipeline.
--
-- Today an airport ride reaches a driver only via the same 30-second
-- countdown offer card as any other ride (dispatch_offers, created by
-- the Node dispatch server in server/index.js) — no full trip detail is
-- shown before the driver decides, and it's a single timed card, not a
-- browsable list. This adds a second, parallel path modeled on the
-- existing negotiation screen (security-35, watchOpenNegotiableRides):
-- a plain Realtime-driven list of open airport rides with no expiry, a
-- notification badge counting them, and a real Accept/Reject per ride
-- (driver-initiated, unlike ride_price_offers' customer-side accept).
--
-- This does NOT touch or replace the existing dispatch_offers flow for
-- airport rides — both paths race to accept the same rides.rows; the
-- `driver_phone is null` guard on the UPDATE (same pattern as
-- accept_dispatch_offer) makes whichever one gets there first win, the
-- other's driver_phone-is-null check just fails harmlessly.
-- ═══════════════════════════════════════════════════════════════

-- ---------------------------------------------------------------------
-- 1) Per-driver reject list — so a driver who rejects an airport ride
--    doesn't keep seeing it resurface in their own list (unlike
--    dispatch_offers rejects, there's no timed offer row to mark
--    rejected here; this is the closest equivalent).
-- ---------------------------------------------------------------------
create table if not exists public.airport_ride_rejections (
  ride_id uuid not null,
  driver_phone text not null,
  created_at timestamptz not null default now(),
  primary key (ride_id, driver_phone)
);
create index if not exists airport_ride_rejections_driver_idx on public.airport_ride_rejections (driver_phone);

alter table public.airport_ride_rejections enable row level security;
drop policy if exists airport_ride_rejections_select_all on public.airport_ride_rejections;
create policy airport_ride_rejections_select_all on public.airport_ride_rejections for select to anon, authenticated using (true);
revoke insert, update, delete on public.airport_ride_rejections from anon, authenticated;
grant select on public.airport_ride_rejections to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) accept_airport_ride — same vehicle-category/quality-tier guards
--    and driver_phone-is-null concurrency lock as accept_dispatch_offer
--    (security-10), just against rides directly since there's no
--    dispatch_offers row backing this path.
-- ---------------------------------------------------------------------
create or replace function public.accept_airport_ride(
  p_ride_id      uuid,
  p_driver_phone text,
  p_driver_name  text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_required_cat    text;
  v_required_tier   text;
  v_driver_cat      text;
  v_driver_has_ac   boolean;
  v_driver_is_clean boolean;
  v_driver_year     int;
  v_tier_ok         boolean;
  v_row             jsonb;
begin
  select airport_vehicle_category, airport_quality_tier
    into v_required_cat, v_required_tier
  from public.rides
  where id = p_ride_id and ride_type = 'airport' and status = 'pending' and driver_phone is null;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'already_taken');
  end if;

  if v_required_cat is not null or v_required_tier is not null then
    select vehicle_category, has_ac, is_clean, vehicle_year
      into v_driver_cat, v_driver_has_ac, v_driver_is_clean, v_driver_year
    from public.driver_applications
    where phone = p_driver_phone and status = 'approved'
    order by created_at desc
    limit 1;

    if v_required_cat is not null and v_driver_cat is distinct from v_required_cat then
      return jsonb_build_object('ok', false, 'reason', 'vehicle_category_mismatch');
    end if;

    if v_required_tier is not null then
      v_tier_ok := case v_required_tier
        when 'ac'      then coalesce(v_driver_has_ac, false)
        when 'clean'   then coalesce(v_driver_is_clean, false)
        when 'modern'  then coalesce(v_driver_year, 0) >= (extract(year from now())::int - 3)
        when 'regular' then not coalesce(v_driver_has_ac, false) and not coalesce(v_driver_is_clean, false)
        else true
      end;

      if not v_tier_ok then
        return jsonb_build_object('ok', false, 'reason', 'quality_tier_mismatch');
      end if;
    end if;
  end if;

  update public.rides
     set status = 'accepted', driver_phone = p_driver_phone,
         driver_name = coalesce(p_driver_name, driver_name), accepted_at = now()
   where id = p_ride_id and driver_phone is null
   returning to_jsonb(rides.*) into v_row;

  if v_row is null then
    return jsonb_build_object('ok', false, 'reason', 'already_taken');
  end if;

  return jsonb_build_object('ok', true, 'data', v_row);
end;
$$;

revoke all on function public.accept_airport_ride(uuid, text, text) from public;
grant execute on function public.accept_airport_ride(uuid, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) reject_airport_ride — just records the reject so it stops showing
--    in that one driver's own list; the ride stays open for everyone
--    else (mirrors how declining a dispatch_offers card only removes it
--    for that driver, not for others still waiting on their own offer).
-- ---------------------------------------------------------------------
create or replace function public.reject_airport_ride(
  p_ride_id      uuid,
  p_driver_phone text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.airport_ride_rejections (ride_id, driver_phone)
  values (p_ride_id, p_driver_phone)
  on conflict (ride_id, driver_phone) do nothing;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.reject_airport_ride(uuid, text) from public;
grant execute on function public.reject_airport_ride(uuid, text) to anon, authenticated;
