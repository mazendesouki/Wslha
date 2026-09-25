-- ═══════════════════════════════════════════════════════════════
-- Real (not just display) vehicle-category matching for ORDERS, per the
-- 7 admin sections' hint badges (security-96 already did this for rides
-- — motorcycle/cargo/box_truck/flatbed excluded from ride offers).
-- Orders previously had ZERO vehicle-category check anywhere — any
-- online driver could accept any order regardless of type.
--
-- required_vehicle_categories_for_order() classifies an order the same
-- way the admin badges do:
--   marketplace (linked via new marketplace_order_id) → per the buyer's
--     chosen shipment_type, same mapping as marketplaceShipmentVehicleCategories
--     in the Flutter app (marketplace_models.dart)
--   courier (store_id='courier')            → cargo, motorcycle
--   merchant_delivery (source)                → motorcycle
--   general_delivery (source)                 → motorcycle, sedan
--   anything else (plain store-purchase order) → sedan, motorcycle
--
-- Enforced in accept_dispatch_offer + accept_missed_request (reject with
-- 'vehicle_category_mismatch'), and get_my_pending_offer(s) now hide an
-- order offer entirely from a driver who isn't eligible, so they never
-- see a popup they can't act on. get_eligible_driver_phones_for_order
-- lets the dispatch engine (server/index.js) pre-filter candidates
-- instead of offering to everyone and relying on the reject path.
--
-- Verified live (test rows created + cleaned up): required_vehicle_
-- categories_for_order correctly classified general_delivery/merchant_
-- delivery/plain-store orders and a marketplace order linked via
-- marketplace_order_id (shipment_type='furniture' → ['box_truck']);
-- driver_eligible_for_order and get_eligible_driver_phones_for_order
-- correctly included/excluded a sedan vs a motorcycle test driver for a
-- merchant_delivery order.
-- ═══════════════════════════════════════════════════════════════
set search_path = public, extensions;

alter table public.orders add column if not exists marketplace_order_id text;

-- ── request_marketplace_delivery: link the orders row back to its marketplace_orders row ──
create or replace function public.request_marketplace_delivery(
  p_item_id text,
  p_buyer_phone text,
  p_buyer_name text,
  p_buyer_address text,
  p_shipment_type text default null
)
returns marketplace_orders
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_item record;
  v_row public.marketplace_orders;
  v_fee numeric := 25;
  v_code text;
  v_default_lat double precision := 31.425;
  v_default_lng double precision := 31.81;
  v_shipment_label text;
begin
  select * into v_item from public.marketplace_items where id = p_item_id and status = 'active';
  if v_item.id is null then raise exception 'item_not_available'; end if;

  v_shipment_label := case p_shipment_type
    when 'products' then 'منتجات'
    when 'car' then 'سيارة'
    when 'furniture' then 'أثاث'
    when 'home_appliances' then 'أجهزة منزلية'
    when 'spare_parts' then 'قطع غيار'
    when 'other' then 'غير ذلك'
    else null
  end;

  insert into public.marketplace_orders (item_id, buyer_phone, buyer_name, buyer_address, seller_phone, price, delivery_fee, total, shipment_type)
  values (p_item_id, p_buyer_phone, p_buyer_name, p_buyer_address, v_item.seller_phone, v_item.price, v_fee, v_item.price + v_fee, p_shipment_type)
  returning * into v_row;

  v_code := 'WSL-' || extract(year from now())::text || '-' || lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  insert into public.orders (
    code, store_id, store_name, store_emoji,
    customer_name, customer_phone, address,
    items, items_summary, subtotal, delivery_fee, total,
    payment, status, accepted_at, store_lat, store_lng, notes, marketplace_order_id
  ) values (
    v_code, null, 'سوق المستعمل — ' || v_item.title, '📦',
    p_buyer_name, p_buyer_phone, p_buyer_address,
    jsonb_build_array(jsonb_build_object('name', v_item.title, 'qty', 1, 'price', v_item.price)),
    v_item.title, v_item.price, v_fee, v_item.price + v_fee,
    'cash', 'preparing', now(),
    coalesce(v_item.lat, v_default_lat), coalesce(v_item.lng, v_default_lng),
    case when v_shipment_label is not null then 'نوع الشحنة: ' || v_shipment_label else null end,
    v_row.id
  );

  return v_row;
end;
$function$;
grant execute on function public.request_marketplace_delivery(text, text, text, text, text) to anon, authenticated, service_role;

-- ── classification ──
create or replace function public.required_vehicle_categories_for_order(p_order_id text)
returns text[]
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_order record;
  v_shipment_type text;
begin
  select store_id, source, marketplace_order_id into v_order
  from public.orders where id::text = p_order_id;

  if v_order.marketplace_order_id is not null then
    select shipment_type into v_shipment_type
    from public.marketplace_orders where id = v_order.marketplace_order_id;

    return case v_shipment_type
      when 'car'             then array['flatbed']
      when 'furniture'       then array['box_truck']
      when 'home_appliances' then array['box_truck']
      when 'spare_parts'     then array['motorcycle']
      else array['sedan', 'cargo'] -- 'products' / 'other' / unset
    end;
  end if;

  if v_order.store_id = 'courier' then
    return array['cargo', 'motorcycle'];
  end if;

  if v_order.source = 'merchant_delivery' then
    return array['motorcycle'];
  end if;

  if v_order.source = 'general_delivery' then
    return array['motorcycle', 'sedan'];
  end if;

  -- plain store-purchase order (store_id set to a real store) or
  -- anything unclassified — the "normal delivery" default.
  return array['sedan', 'motorcycle'];
end;
$$;
grant execute on function public.required_vehicle_categories_for_order(text) to anon, authenticated, service_role;

-- ── per-driver eligibility check ──
create or replace function public.driver_eligible_for_order(p_driver_phone text, p_order_id text)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(
    (
      select da.vehicle_category
      from public.driver_applications da
      where da.phone = p_driver_phone and da.status = 'approved'
      order by da.created_at desc
      limit 1
    ) = any(public.required_vehicle_categories_for_order(p_order_id)),
    false
  );
$$;
grant execute on function public.driver_eligible_for_order(text, text) to anon, authenticated, service_role;

-- ── candidate list for the dispatch engine (server/index.js) ──
create or replace function public.get_eligible_driver_phones_for_order(p_order_id text)
returns table(driver_phone text, driver_name text, lat double precision, lng double precision)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select dl.driver_phone, dl.driver_name, dl.lat, dl.lng
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
    and dl.updated_at > now() - interval '3 minutes'
    and da.vehicle_category = any(public.required_vehicle_categories_for_order(p_order_id));
$$;
grant execute on function public.get_eligible_driver_phones_for_order(text) to anon, authenticated, service_role;

-- ── get_my_pending_offer: hide an order offer the driver can't accept ──
create or replace function public.get_my_pending_offer(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer public.dispatch_offers;
  v_data  jsonb;
  v_ride_negotiable boolean;
  v_ride_type text;
  v_driver_cat text;
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
    select vehicle_category into v_driver_cat
    from public.driver_applications
    where phone::text = p_driver_phone
    order by created_at desc
    limit 1;
    if v_driver_cat in ('motorcycle', 'cargo', 'box_truck', 'flatbed') then return null; end if;

    select to_jsonb(r), coalesce(r.is_negotiable, false), r.ride_type into v_data, v_ride_negotiable, v_ride_type
    from public.rides r where r.id::text = v_offer.target_id;
    if v_ride_negotiable or v_ride_type = 'airport' then return null; end if;
  else
    if not public.driver_eligible_for_order(p_driver_phone, v_offer.target_id) then return null; end if;
    select to_jsonb(o) into v_data from public.orders o where o.id::text = v_offer.target_id;
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
grant execute on function public.get_my_pending_offer(text) to anon, authenticated;

-- ── get_my_pending_offers: same, for the plural list ──
create or replace function public.get_my_pending_offers(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_driver_cat text;
begin
  select vehicle_category into v_driver_cat
  from public.driver_applications
  where phone::text = p_driver_phone
  order by created_at desc
  limit 1;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'offer_id', d.id,
        'target_type', d.target_type,
        'expires_at', d.expires_at,
        'data', case when d.target_type = 'ride' then to_jsonb(r) else to_jsonb(ord) end
      )
      order by d.offered_at desc
    ),
    '[]'::jsonb
  ) into v_result
  from public.dispatch_offers d
  left join public.rides  r   on d.target_type = 'ride'  and r.id::text = d.target_id
  left join public.orders ord on d.target_type = 'order' and ord.id::text = d.target_id
  where d.driver_phone = p_driver_phone
    and d.status = 'pending'
    and d.expires_at > now()
    and ((d.target_type = 'ride' and r.id is not null and coalesce(r.is_negotiable, false) = false
          and coalesce(r.ride_type, '') <> 'airport'
          and (v_driver_cat is null or v_driver_cat not in ('motorcycle', 'cargo', 'box_truck', 'flatbed')))
         or (d.target_type = 'order' and ord.id is not null and public.driver_eligible_for_order(d.driver_phone, d.target_id)));

  return v_result;
end;
$$;
grant execute on function public.get_my_pending_offers(text) to anon, authenticated;

-- ── accept_dispatch_offer: enforce on the order branch ──
create or replace function public.accept_dispatch_offer(p_offer_id text, p_driver_phone text, p_driver_name text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_offer public.dispatch_offers;
  v_row   jsonb;
  v_required_cat   text;
  v_required_tier  text;
  v_driver_cat     text;
  v_driver_has_ac  boolean;
  v_driver_is_clean boolean;
  v_driver_is_modern boolean;
  v_tier_ok        boolean;
begin
  select * into v_offer
  from public.dispatch_offers
  where id::text = p_offer_id and driver_phone::text = p_driver_phone
  for update;

  if not found or v_offer.status <> 'pending' or v_offer.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'expired_or_taken');
  end if;

  if v_offer.target_type = 'ride' then
    select vehicle_category into v_driver_cat
    from public.driver_applications
    where phone::text = p_driver_phone
    order by created_at desc
    limit 1;

    if v_driver_cat in ('motorcycle', 'cargo', 'box_truck', 'flatbed') then
      update public.dispatch_offers set status = 'rejected', responded_at = now() where id::text = p_offer_id;
      return jsonb_build_object('ok', false, 'reason', 'delivery_only_vehicle');
    end if;

    select airport_vehicle_category, airport_quality_tier
      into v_required_cat, v_required_tier
    from public.rides
    where id::text = v_offer.target_id;

    if v_required_cat is not null or v_required_tier is not null then
      select vehicle_category, has_ac, is_clean, is_modern
        into v_driver_cat, v_driver_has_ac, v_driver_is_clean, v_driver_is_modern
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
          when 'modern'  then coalesce(v_driver_is_modern, false)
          when 'regular' then not coalesce(v_driver_has_ac, false) and not coalesce(v_driver_is_clean, false) and not coalesce(v_driver_is_modern, false)
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
    if not public.driver_eligible_for_order(p_driver_phone, v_offer.target_id) then
      update public.dispatch_offers set status = 'rejected', responded_at = now() where id::text = p_offer_id;
      return jsonb_build_object('ok', false, 'reason', 'vehicle_category_mismatch');
    end if;

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
$function$;
grant execute on function public.accept_dispatch_offer(text, text, text) to anon, authenticated;

-- ── accept_missed_request: mirror the same order-branch check ──
create or replace function public.accept_missed_request(p_offer_id text, p_driver_phone text, p_driver_name text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_offer public.dispatch_offers;
  v_row   jsonb;
  v_required_cat   text;
  v_required_tier  text;
  v_driver_cat     text;
  v_driver_has_ac  boolean;
  v_driver_is_clean boolean;
  v_driver_is_modern boolean;
  v_tier_ok        boolean;
begin
  select * into v_offer
  from public.dispatch_offers
  where id::text = p_offer_id and driver_phone::text = p_driver_phone
  for update;

  if not found or v_offer.status <> 'expired' then
    return jsonb_build_object('ok', false, 'reason', 'not_a_missed_request');
  end if;

  if v_offer.target_type = 'ride' then
    select airport_vehicle_category, airport_quality_tier
      into v_required_cat, v_required_tier
    from public.rides
    where id::text = v_offer.target_id;

    if v_required_cat is not null or v_required_tier is not null then
      select vehicle_category, has_ac, is_clean, is_modern
        into v_driver_cat, v_driver_has_ac, v_driver_is_clean, v_driver_is_modern
      from public.driver_applications
      where phone::text = p_driver_phone and status = 'approved'
      order by created_at desc
      limit 1;

      if v_required_cat is not null and v_driver_cat is distinct from v_required_cat then
        return jsonb_build_object('ok', false, 'reason', 'vehicle_category_mismatch');
      end if;

      if v_required_tier is not null then
        v_tier_ok := case v_required_tier
          when 'ac'      then coalesce(v_driver_has_ac, false)
          when 'clean'   then coalesce(v_driver_is_clean, false)
          when 'modern'  then coalesce(v_driver_is_modern, false)
          when 'regular' then not coalesce(v_driver_has_ac, false) and not coalesce(v_driver_is_clean, false) and not coalesce(v_driver_is_modern, false)
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
     where id::text = v_offer.target_id and driver_phone is null and status = 'pending'
     returning to_jsonb(rides.*) into v_row;
  else
    if not public.driver_eligible_for_order(p_driver_phone, v_offer.target_id) then
      return jsonb_build_object('ok', false, 'reason', 'vehicle_category_mismatch');
    end if;

    update public.orders
       set status = 'on_the_way', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), picked_up_at = null
     where id::text = v_offer.target_id and driver_phone is null and status = 'preparing'
     returning to_jsonb(orders.*) into v_row;
  end if;

  if v_row is null then
    update public.dispatch_offers set driver_dismissed_at = now() where id::text = p_offer_id;
    return jsonb_build_object('ok', false, 'reason', 'already_taken');
  end if;

  update public.dispatch_offers set driver_dismissed_at = now() where id::text = p_offer_id;

  return jsonb_build_object('ok', true, 'target_type', v_offer.target_type, 'data', v_row);
end;
$function$;
grant execute on function public.accept_missed_request(text, text, text) to anon, authenticated;

-- ── driver_claim_delivery_order: legacy broadcast-fallback order claim
--    (driver-dashboard.astro's poll fallback) — found while auditing
--    accept paths that this second one had zero vehicle-category check,
--    bypassing the restriction just added above. ──
create or replace function public.driver_claim_delivery_order(p_order_id uuid, p_driver_phone text, p_driver_name text default null)
returns setof orders
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare v_driver_status text;
begin
  select status into v_driver_status
  from public.driver_applications
  where phone::text = p_driver_phone
  order by created_at desc
  limit 1;
  if v_driver_status is distinct from 'approved' then
    raise exception 'driver_not_approved';
  end if;

  if not public.driver_eligible_for_order(p_driver_phone, p_order_id::text) then
    raise exception 'vehicle_category_mismatch';
  end if;

  return query
    update public.orders
       set status = 'on_the_way', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), picked_up_at = null
     where id = p_order_id and driver_phone is null and status = 'preparing'
     returning orders.*;
end;
$function$;
grant execute on function public.driver_claim_delivery_order(uuid, text, text) to anon, authenticated;

-- ── driver_accept_ride: legacy broadcast-fallback ride accept — still
--    only excluded ('motorcycle','cargo'), missed by security-96's
--    box_truck/flatbed extension since that migration only touched
--    accept_dispatch_offer/get_my_pending_offer(s)/submit_ride_price_offer,
--    not this one. ──
create or replace function public.driver_accept_ride(p_ride_id uuid, p_driver_phone text, p_driver_name text default null)
returns setof rides
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare v_driver_status text; v_driver_cat text;
begin
  select status, vehicle_category into v_driver_status, v_driver_cat
  from public.driver_applications
  where phone::text = p_driver_phone
  order by created_at desc
  limit 1;

  if v_driver_status is distinct from 'approved' then
    raise exception 'driver_not_approved';
  end if;
  if v_driver_cat in ('motorcycle', 'cargo', 'box_truck', 'flatbed') then
    raise exception 'delivery_only_vehicle';
  end if;

  return query
    update public.rides
       set status = 'accepted', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), accepted_at = now()
     where id = p_ride_id and driver_phone is null and status = 'pending'
     returning rides.*;
end;
$function$;
grant execute on function public.driver_accept_ride(uuid, text, text) to anon, authenticated;
