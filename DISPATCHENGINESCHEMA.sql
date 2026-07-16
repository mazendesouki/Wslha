-- ═══════════════════════════════════════════════════════════════
-- Dispatch engine schema — targeted, sequential nearest-driver
-- offers instead of broadcast-to-everyone. Run once in the
-- Supabase SQL Editor BEFORE deploying the dispatch server.
-- ═══════════════════════════════════════════════════════════════

-- Busy-tracking for delivery orders (rides already use driver_locations.ride_id).
alter table public.driver_locations add column if not exists current_order_id text;

-- One offer = "this ride/order was offered to this driver, expires at X".
create table if not exists public.dispatch_offers (
  id            text primary key,
  target_type   text not null check (target_type in ('ride','order')),
  target_id     text not null,
  driver_phone  text not null,
  status        text not null default 'pending' check (status in ('pending','accepted','rejected','expired')),
  offered_at    timestamptz not null default now(),
  expires_at    timestamptz not null,
  responded_at  timestamptz
);
create index if not exists dispatch_offers_driver_pending_idx
  on public.dispatch_offers (driver_phone, status);
create index if not exists dispatch_offers_target_idx
  on public.dispatch_offers (target_type, target_id);

-- Only RPCs touch this table from the client (service-role key used by
-- the dispatch server bypasses RLS/grants entirely, same as every other
-- privileged table in this project).
revoke all on public.dispatch_offers from anon, authenticated;

-- ── Driver polls this to see if THEY specifically have an offer ──
create or replace function public.get_my_pending_offer(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer public.dispatch_offers;
  v_data  jsonb;
begin
  select * into v_offer
  from public.dispatch_offers
  where driver_phone = p_driver_phone
    and status = 'pending'
    and expires_at > now()
  order by offered_at desc
  limit 1;

  if not found then return null; end if;

  if v_offer.target_type = 'ride' then
    select to_jsonb(r) into v_data from public.rides r where r.id = v_offer.target_id;
  else
    select to_jsonb(o) into v_data from public.orders o where o.id = v_offer.target_id;
  end if;

  if v_data is null then return null; end if;

  return jsonb_build_object(
    'offer_id',    v_offer.id,
    'target_type', v_offer.target_type,
    'expires_at',  v_offer.expires_at,
    'data',        v_data
  );
end;
$$;

revoke all on function public.get_my_pending_offer(text) from public;
grant execute on function public.get_my_pending_offer(text) to anon, authenticated;

-- ── Atomic accept: only succeeds if the offer is still pending AND
--    the ride/order is still unclaimed (protects against a race with
--    the legacy broadcast fallback in driver-dashboard.astro). ──
create or replace function public.accept_dispatch_offer(
  p_offer_id    text,
  p_driver_phone text,
  p_driver_name  text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer public.dispatch_offers;
  v_row   jsonb;
begin
  select * into v_offer
  from public.dispatch_offers
  where id = p_offer_id and driver_phone = p_driver_phone
  for update;

  if not found or v_offer.status <> 'pending' or v_offer.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'expired_or_taken');
  end if;

  if v_offer.target_type = 'ride' then
    update public.rides
       set status = 'accepted', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), accepted_at = now()
     where id = v_offer.target_id and driver_phone is null
     returning to_jsonb(rides.*) into v_row;
  else
    update public.orders
       set status = 'on_the_way', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), picked_up_at = null
     where id = v_offer.target_id and driver_phone is null and status = 'preparing'
     returning to_jsonb(orders.*) into v_row;
  end if;

  if v_row is null then
    update public.dispatch_offers set status = 'expired', responded_at = now() where id = p_offer_id;
    return jsonb_build_object('ok', false, 'reason', 'already_taken');
  end if;

  update public.dispatch_offers set status = 'accepted', responded_at = now() where id = p_offer_id;

  return jsonb_build_object('ok', true, 'target_type', v_offer.target_type, 'data', v_row);
end;
$$;

revoke all on function public.accept_dispatch_offer(text, text, text) from public;
grant execute on function public.accept_dispatch_offer(text, text, text) to anon, authenticated;

-- ── Driver explicitly declines — lets the server move to the next
--    nearest candidate immediately instead of waiting out the full 30s. ──
create or replace function public.reject_dispatch_offer(p_offer_id text, p_driver_phone text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.dispatch_offers
     set status = 'rejected', responded_at = now()
   where id = p_offer_id and driver_phone = p_driver_phone and status = 'pending';
$$;

revoke all on function public.reject_dispatch_offer(text, text) from public;
grant execute on function public.reject_dispatch_offer(text, text) to anon, authenticated;
