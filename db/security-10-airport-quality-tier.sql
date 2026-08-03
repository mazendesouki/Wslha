-- ═══════════════════════════════════════════════════════════════
-- Airport-ride service-quality eligibility check.
--
-- The customer app lets a customer request a quality tier for an airport
-- ride (عادية/نظيفة/مكيّفة/موديل حديث — see
-- flutter_app/lib/features/airport/airport_fare.dart's qualityMultiplier).
-- That was previously just a price multiplier + a note left for the
-- driver — nothing stopped a driver whose registered car doesn't actually
-- have AC (etc.) from accepting an "AC" ride. This adds the same kind of
-- accept-time guard security-09 added for vehicle_category: a driver can
-- still see the offer, but accepting it is rejected server-side if their
-- driver_applications row doesn't match what was requested.
--
-- Same limitation as security-09: this does not change candidate
-- selection in the Node dispatch server (server/index.js), which still
-- offers the ride to nearby drivers regardless of tier — only accept is
-- guarded.
--
-- Tier semantics (checked against the driver's latest approved
-- driver_applications row):
--   'ac'      -> has_ac = true
--   'clean'   -> is_clean = true
--   'modern'  -> vehicle_year >= (current year - 3)
--   'regular' -> has_ac = false and is_clean = false
--   null / anything else -> no requirement (back-compat with older rides)
-- ═══════════════════════════════════════════════════════════════

alter table public.rides add column if not exists airport_quality_tier text;

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
begin
  select * into v_offer
  from public.dispatch_offers
  where id = p_offer_id and driver_phone = p_driver_phone
  for update;

  if not found or v_offer.status <> 'pending' or v_offer.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'expired_or_taken');
  end if;

  if v_offer.target_type = 'ride' then
    select airport_vehicle_category, airport_quality_tier
      into v_required_cat, v_required_tier
    from public.rides
    where id = v_offer.target_id and ride_type = 'airport';

    if v_required_cat is not null or v_required_tier is not null then
      select vehicle_category, has_ac, is_clean, vehicle_year
        into v_driver_cat, v_driver_has_ac, v_driver_is_clean, v_driver_year
      from public.driver_applications
      where phone = p_driver_phone and status = 'approved'
      order by created_at desc
      limit 1;

      if v_required_cat is not null and v_driver_cat is distinct from v_required_cat then
        update public.dispatch_offers set status = 'rejected', responded_at = now() where id = p_offer_id;
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
          update public.dispatch_offers set status = 'rejected', responded_at = now() where id = p_offer_id;
          return jsonb_build_object('ok', false, 'reason', 'quality_tier_mismatch');
        end if;
      end if;
    end if;

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
