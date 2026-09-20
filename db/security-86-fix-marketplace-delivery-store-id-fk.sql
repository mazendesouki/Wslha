-- =====================================================================
--  وصّلها — Security #86: إصلاح باگ حقيقي في طلب توصيل سوق المستعمل
--
--  زرار "اطلب توصيل عبر وصّلها" في صفحة إعلان سوق المستعمل كان بيرجع
--  "حدث خطأ، حاول مرة أخرى" دايمًا. السبب: request_marketplace_delivery()
--  كانت بتحط القيمة الحرفية 'marketplace' في orders.store_id، وorders.
--  store_id عليه foreign key حقيقي على stores(id) — فالـ INSERT كان بيفشل
--  بـ "violates foreign key constraint" لأن 'marketplace' مش UUID حقيقي
--  موجود في جدول stores. النمط الصح (المستخدم بالفعل لطلبات الطرود
--  courier) هو ترك store_id فاضي (NULL) — عمود nullable أصلاً، وكل
--  الكود اللي بيفحصه (security-18/25/45/54) بيتعامل مع NULL بشكل صحيح.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

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
    'cash', 'preparing', now(), v_default_lat, v_default_lng
  );

  return v_row;
end;
$$;
