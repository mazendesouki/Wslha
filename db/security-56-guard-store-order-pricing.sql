-- =====================================================================
--  وصّلها — Security #56: منع التلاعب في سعر طلبات المتاجر (الأخطر ماليًا)
--
--  الثغرة: طلب checkout_sheet.dart / store/[id].astro's بيعمل INSERT
--  مباشر على جدول orders، وكل قيم subtotal/total/price بتيجي من
--  التطبيق نفسه بدون أي إعادة حساب أو تحقق من السيرفر — مختلف تمامًا عن
--  general_delivery/merchant_delivery (security-12/13) اللي عندهم
--  تريجر بيعيد حساب الرسوم فعليًا. أي حد معاه الـ anon key (مكتوب في
--  كود التطبيق أصلاً، مش سري) يقدر يبعت INSERT مباشر بـ total = 1 جنيه
--  بدل السعر الحقيقي، أو أسعار سالبة، ويشتري أي حاجة بأي سعر يحدده هو.
--
--  الحل: تريجر BEFORE INSERT بيعيد حساب subtotal/delivery_fee/total من
--  صفوف products/stores الحقيقية — مش من القيم اللي بعتها التطبيق —
--  لأي طلب متجر عادي (مش general_delivery/merchant_delivery/courier،
--  دول عندهم تريجرز منفصلة بالفعل).
--
--  قيد معروف ومقصود: بعض المتاجر عندها قوائم أصناف "ثابتة" (Static)
--  مكتوبة في كود الموقع نفسه (src/data/stores.ts) بدل صفوف حقيقية في
--  جدول products — أصناف زي دي مالهاش id حقيقي في products، فالتريجر
--  بيثق في السعر اللي بعته التطبيق لها بس (زي ما كان الوضع قبل كده
--  بالظبط، مفيش تراجع). أي صنف عنده id بيتطابق مع صف حقيقي في products
--  بقى سعره يتقفل من السيرفر، مش من التطبيق.
--
--  لازم تحدّث الكود بعد تشغيل الملف ده (flutter checkout_sheet.dart
--  بيبعت id لكل صنف دلوقتي — موجود في نفس الكوميت؛ store/[id].astro
--  كان بيبعت id بالفعل من زمان، مفيش تغيير مطلوب فيه).
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.guard_store_order_pricing()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_item              jsonb;
  v_qty               numeric;
  v_product_price     numeric;
  v_computed_subtotal numeric := 0;
  v_store_delivery_fee numeric;
begin
  -- general_delivery/merchant_delivery (security-12/13) وطلبات courier
  -- عندهم منطق رسوم منفصل بالفعل ومفيهمش صفوف products حقيقية أصلاً —
  -- وطلب من غير store_id مش طلب متجر خالص.
  if new.store_id is null
     or new.store_id = 'courier'
     or new.source in ('general_delivery', 'merchant_delivery') then
    return new;
  end if;

  if new.items is null or jsonb_typeof(new.items) <> 'array' then
    return new;
  end if;

  for v_item in select * from jsonb_array_elements(new.items)
  loop
    v_qty := coalesce((v_item->>'qty')::numeric, 1);
    if v_qty <= 0 then
      raise exception 'invalid_item_quantity';
    end if;

    v_product_price := null;
    if v_item->>'id' is not null then
      select price into v_product_price
        from public.products
       where id::text = v_item->>'id' and store_id::text = new.store_id::text;
    end if;

    if v_product_price is not null then
      -- صنف حقيقي في products — السعر بتاعه بيتقفل من هنا، مش من التطبيق.
      v_computed_subtotal := v_computed_subtotal + v_product_price * v_qty;
    else
      -- صنف "ثابت" (Static) من غير صف حقيقي في products — بنثق في
      -- السعر اللي بعته التطبيق زي ما كان الوضع قبل التريجر ده.
      v_computed_subtotal := v_computed_subtotal + coalesce((v_item->>'price')::numeric, 0) * v_qty;
    end if;
  end loop;

  select delivery_fee into v_store_delivery_fee from public.stores where id::text = new.store_id::text;

  new.subtotal := v_computed_subtotal;
  new.delivery_fee := coalesce(v_store_delivery_fee, new.delivery_fee, 0);
  new.total := v_computed_subtotal + new.delivery_fee;

  return new;
end;
$$;

drop trigger if exists trg_guard_store_order_pricing on public.orders;
create trigger trg_guard_store_order_pricing
  before insert on public.orders
  for each row execute function public.guard_store_order_pricing();
