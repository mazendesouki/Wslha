-- =====================================================================
--  وصّلها — Security #87: إحداثيات حقيقية لإعلانات سوق المستعمل
--
--  عشان طلب التوصيل (request_marketplace_delivery — security-86) يوصل
--  لسائق حقيقي قريب فعليًا من المنتج (مش نقطة افتراضية ثابتة في نص
--  دمياط الجديدة)، لازم كل إعلان يحمل إحداثيات حقيقية. الأعمدة دي
--  اختيارية (nullable) — إعلان قديم من غير إحداثيات (أو معمول من غير
--  تحديد موقع) لسه بيرجع للنقطة الافتراضية كـ fallback، مش بيتكسر.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.marketplace_items
  add column if not exists lat double precision,
  add column if not exists lng double precision;

-- request_marketplace_delivery() يستخدم إحداثيات الإعلان الحقيقية لو
-- موجودة، وإلا يرجع لنفس النقطة الافتراضية القديمة (مركز دمياط الجديدة)
-- بدل ما يفشل أو يسيب store_lat/lng فاضية.
create or replace function public.request_marketplace_delivery(
  p_item_id text, p_buyer_phone text, p_buyer_name text, p_buyer_address text
) returns marketplace_orders
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_item record;
  v_row public.marketplace_orders;
  v_fee numeric := 25;
  v_code text;
  v_default_lat double precision := 31.425;
  v_default_lng double precision := 31.81;
begin
  select * into v_item from public.marketplace_items where id = p_item_id and status = 'active';
  if v_item.id is null then raise exception 'item_not_available'; end if;

  insert into public.marketplace_orders (item_id, buyer_phone, buyer_name, buyer_address, seller_phone, price, delivery_fee, total)
  values (p_item_id, p_buyer_phone, p_buyer_name, p_buyer_address, v_item.seller_phone, v_item.price, v_fee, v_item.price + v_fee)
  returning * into v_row;

  v_code := 'WSL-' || extract(year from now())::text || '-' || lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  insert into public.orders (
    code, store_id, store_name, store_emoji,
    customer_name, customer_phone, address,
    items, items_summary, subtotal, delivery_fee, total,
    payment, status, accepted_at, store_lat, store_lng
  ) values (
    v_code, null, 'سوق المستعمل — ' || v_item.title, '📦',
    p_buyer_name, p_buyer_phone, p_buyer_address,
    jsonb_build_array(jsonb_build_object('name', v_item.title, 'qty', 1, 'price', v_item.price)),
    v_item.title, v_item.price, v_fee, v_item.price + v_fee,
    'cash', 'preparing', now(),
    coalesce(v_item.lat, v_default_lat), coalesce(v_item.lng, v_default_lng)
  );

  return v_row;
end;
$$;
