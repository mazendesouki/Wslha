-- ═══════════════════════════════════════════════════════════════
-- Airport-ride vehicle-category eligibility check.
--
-- Previously any approved+online driver could accept an airport ride
-- regardless of vehicle category (customer picks سيدان/SUV/ميكروباص when
-- booking, but nothing enforced a matching driver on accept). This adds
-- a lightweight server-side guard on accept_dispatch_offer — it does NOT
-- change candidate selection in the separate Node dispatch server
-- (server/index.js), which still offers airport rides to nearby drivers
-- regardless of category; a mismatched driver now just gets rejected
-- with a clear reason when they try to accept, instead of silently
-- taking a trip they can't actually fulfil.
-- ═══════════════════════════════════════════════════════════════

alter table public.rides add column if not exists airport_vehicle_category text;

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
  v_required_cat text;
  v_driver_cat   text;
begin
  select * into v_offer
  from public.dispatch_offers
  where id = p_offer_id and driver_phone = p_driver_phone
  for update;

  if not found or v_offer.status <> 'pending' or v_offer.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'expired_or_taken');
  end if;

  if v_offer.target_type = 'ride' then
    select airport_vehicle_category into v_required_cat
    from public.rides
    where id = v_offer.target_id and ride_type = 'airport';

    if v_required_cat is not null then
      select vehicle_category into v_driver_cat
      from public.driver_applications
      where phone = p_driver_phone and status = 'approved'
      order by created_at desc
      limit 1;

      if v_driver_cat is distinct from v_required_cat then
        update public.dispatch_offers set status = 'rejected', responded_at = now() where id = p_offer_id;
        return jsonb_build_object('ok', false, 'reason', 'vehicle_category_mismatch');
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
