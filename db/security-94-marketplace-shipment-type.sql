-- ═══════════════════════════════════════════════════════════════
-- سوق المستعمل: adds an optional "نوع الشحنة" (shipment type) field to
-- the delivery-request flow — منتجات/سيارة/أثاث/أجهزة منزلية/قطع غيار/
-- غير ذلك — so the driver knows what kind of item they're picking up
-- before accepting. Purely informational for now (no fee/vehicle-
-- category logic change): stored on marketplace_orders and surfaced in
-- the dispatched orders row's `notes` so it's visible wherever notes
-- already render for drivers/admin.
--
-- Signature grows from 4 to 5 args (new one has a default, so existing
-- 4-arg callers — the web app's requestDelivery() — keep working
-- unchanged); dropped the old 4-arg overload first so there's a single
-- function to maintain, same pattern as security-93's
-- get_driver_missed_requests rewrite.
-- ═══════════════════════════════════════════════════════════════

alter table public.marketplace_orders add column if not exists shipment_type text;

drop function if exists public.request_marketplace_delivery(text, text, text, text);

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
    payment, status, accepted_at, store_lat, store_lng, notes
  ) values (
    v_code, null, 'سوق المستعمل — ' || v_item.title, '📦',
    p_buyer_name, p_buyer_phone, p_buyer_address,
    jsonb_build_array(jsonb_build_object('name', v_item.title, 'qty', 1, 'price', v_item.price)),
    v_item.title, v_item.price, v_fee, v_item.price + v_fee,
    'cash', 'preparing', now(),
    coalesce(v_item.lat, v_default_lat), coalesce(v_item.lng, v_default_lng),
    case when v_shipment_label is not null then 'نوع الشحنة: ' || v_shipment_label else null end
  );

  return v_row;
end;
$function$;

grant execute on function public.request_marketplace_delivery(text, text, text, text, text) to anon, authenticated, service_role;
