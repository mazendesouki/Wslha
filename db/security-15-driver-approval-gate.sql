-- ═══════════════════════════════════════════════════════════════
-- Closes a real gap: accept_dispatch_offer() only ever checked vehicle
-- category / quality tier for AIRPORT rides (airport_vehicle_category is
-- only set on those). For local/external rides and delivery orders,
-- NOTHING checked whether the accepting driver was actually approved by
-- admin_review_application() — any account with role='driver', including
-- one that just registered and never got past the account-creation step,
-- could accept a real ride or order and get paid for it.
--
-- This adds a single approval check at the very top of
-- accept_dispatch_offer(), before the ride/order branching, so it
-- applies uniformly to every dispatch type. A driver whose latest
-- driver_applications row isn't status='approved' gets rejected with a
-- specific reason instead of ever reaching the ride/order assignment.
-- ═══════════════════════════════════════════════════════════════

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
  v_required_cat   text;
  v_required_tier  text;
  v_driver_cat     text;
  v_driver_has_ac  boolean;
  v_driver_is_clean boolean;
  v_driver_year    int;
  v_tier_ok        boolean;
  v_driver_status  text;
begin
  select * into v_offer
  from public.dispatch_offers
  where id::text = p_offer_id and driver_phone::text = p_driver_phone
  for update;

  if not found or v_offer.status <> 'pending' or v_offer.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'expired_or_taken');
  end if;

  select status into v_driver_status
  from public.driver_applications
  where phone::text = p_driver_phone
  order by created_at desc
  limit 1;

  if v_driver_status is distinct from 'approved' then
    update public.dispatch_offers set status = 'rejected', responded_at = now() where id::text = p_offer_id;
    return jsonb_build_object('ok', false, 'reason', 'driver_not_approved');
  end if;

  if v_offer.target_type = 'ride' then
    select airport_vehicle_category, airport_quality_tier
      into v_required_cat, v_required_tier
    from public.rides
    where id::text = v_offer.target_id and ride_type = 'airport';

    if v_required_cat is not null or v_required_tier is not null then
      select vehicle_category, has_ac, is_clean, vehicle_year
        into v_driver_cat, v_driver_has_ac, v_driver_is_clean, v_driver_year
      from public.driver_applications
      where phone::text = p_driver_phone and status = 'approved'
      order by created_at desc
      limit 1;

      if v_required_cat is not null and v_driver_cat is distinct from v_required_cat then
        update public.dispatch_offers set status = 'rejected', responded_at = now() where id::text = p_offer_id;
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
          update public.dispatch_offers set status = 'rejected', responded_at = now() where id::text = p_offer_id;
          return jsonb_build_object('ok', false, 'reason', 'quality_tier_mismatch');
        end if;
      end if;
    end if;

    update public.rides
       set status = 'accepted', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), accepted_at = now()
     where id::text = v_offer.target_id and driver_phone is null
     returning to_jsonb(rides.*) into v_row;
  else
    update public.orders
       set status = 'on_the_way', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), picked_up_at = null
     where id::text = v_offer.target_id and driver_phone is null and status = 'preparing'
     returning to_jsonb(orders.*) into v_row;
  end if;

  if v_row is null then
    update public.dispatch_offers set status = 'expired', responded_at = now() where id::text = p_offer_id;
    return jsonb_build_object('ok', false, 'reason', 'already_taken');
  end if;

  update public.dispatch_offers set status = 'accepted', responded_at = now() where id::text = p_offer_id;

  return jsonb_build_object('ok', true, 'target_type', v_offer.target_type, 'data', v_row);
end;
$$;

revoke all on function public.accept_dispatch_offer(text, text, text) from public;
grant execute on function public.accept_dispatch_offer(text, text, text) to anon, authenticated;
