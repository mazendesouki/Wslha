-- =====================================================================
--  وصّلها — Security #130: فصل "السوق المستعمل" عن "طلبات التوصيل"
--
--  request_marketplace_delivery() بيتحقق من 'marketplace' في أول
--  سطر، لكنه بعدين بيعمل insert في جدول orders (عشان يتوزّع على
--  سائق) — والـ insert ده كان بيتفحص تاني من trg_guard_order_service_control
--  (security-127) اللي بيتحقق من 'delivery_orders'. النتيجة: قفل
--  "طلبات التوصيل" كان بيقفل شراء السوق المستعمل كمان من غير ما
--  يبان ده في لوحة التحكم — والخطأ اللي بيظهر كان "delivery_orders"
--  مش "marketplace"، فمربك للأدمن.
--
--  الحل: trg_guard_order_service_control بيتجاهل الفحص لو الصف الجديد
--  جايّ من السوق المستعمل أصلًا (marketplace_order_id مش فاضي) — لأن
--  الفحص بتاعه ('marketplace') اتعمل أصلًا جوه request_marketplace_delivery()
--  قبل ما يوصل للـ insert ده. الطلبات العادية من المتاجر (delivery_orders)
--  لسه بتتفحص زي ما هي.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public._guard_order_service_control()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.marketplace_order_id is null and not public.is_service_active('delivery_orders') then
    raise exception 'service_unavailable: delivery_orders';
  end if;
  return new;
end;
$$;
