-- =====================================================================
--  وصّلها — Security #141: تطبيع صيغة الرقم في تقييم السائق وأوامر
--  التاجر وتأكيد التسليم
--
--  نفس فئة الباگ اللي اتصلحت في security-136 (send_ride_message):
--  مقارنة رقم بمساواة نصية مباشرة ("=") من غير تطبيع صيغته (01xxxxxxxxx
--  مقابل +20xxxxxxxxx). تأكدنا إن driver_applications.phone فعلاً
--  مخزّن بالصيغتين (مثال حي: صفين بصيغة +20)، فالمخاطرة دي حقيقية —
--  مش نظرية بس — حتى لو مفيش سائق معتمد (approved) حاليًا واقع فيها.
--
--  الدوال اللي اتصلحت:
--  - submit_customer_rating: كانت بترفض تقييم سائق حقيقي لرحلة/طلب
--    خلّصه فعلاً بـ "not_your_trip" لو صيغة رقمه مش مطابقة حرفيًا
--    لـ rides.driver_phone/orders.driver_phone.
--  - merchant_accept_order / merchant_reject_order /
--    merchant_mark_order_ready: كانت بترفض أي عملية على الطلب بـ
--    "not_your_store" لنفس السبب (stores.owner_phone).
--  - confirm_order_delivery: كانت بترجع false (يبان للسائق زي "كود
--    غلط") بدل ما تتعرف عليه كصاحب التوصيل.
--
--  آمن لإعادة التشغيل. مفيش تغيير في شكل أي دالة (نفس البارامترات
--  بالظبط)، فـ CREATE OR REPLACE كفاية من غير أي مخاطرة overload.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.submit_customer_rating(
  p_driver_phone text,
  p_service_type text,
  p_reference_id uuid,
  p_rating integer,
  p_comment text default null,
  p_tags text[] default null
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_customer_phone text; v_id uuid;
  v_driver_variants text[] := array[
    p_driver_phone,
    case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
    case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end
  ];
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'invalid_rating'; end if;

  if p_service_type = 'delivery' then
    select customer_phone into v_customer_phone from public.orders
     where id = p_reference_id and driver_phone = any(v_driver_variants) and status = 'delivered';
  else
    select customer_phone into v_customer_phone from public.rides
     where id = p_reference_id and driver_phone = any(v_driver_variants) and status = 'completed';
  end if;

  if v_customer_phone is null then raise exception 'not_your_trip'; end if;

  if exists (select 1 from public.ratings where ride_id = p_reference_id::text and rated_by = 'driver') then
    raise exception 'already_rated';
  end if;

  v_id := gen_random_uuid();
  insert into public.ratings (id, driver_phone, customer_phone, rating, comment, service_type, ride_id, rated_by, tags, created_at)
  values (v_id, p_driver_phone, v_customer_phone, p_rating, p_comment, p_service_type, p_reference_id::text, 'driver', p_tags, now());

  return v_id::text;
end;
$$;

create or replace function public.merchant_accept_order(p_order_id uuid, p_merchant_phone text, p_prep_minutes integer default null)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_order public.orders%rowtype; v_owns boolean; v_rows int;
  v_merchant_variants text[] := array[
    p_merchant_phone,
    case when p_merchant_phone like '+20%' then '0'||substr(p_merchant_phone,4) else p_merchant_phone end,
    case when p_merchant_phone like '0%'   then '+2'||p_merchant_phone           else p_merchant_phone end
  ];
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'order_not_found'; end if;

  select exists(select 1 from public.stores where id = v_order.store_id and owner_phone = any(v_merchant_variants)) into v_owns;
  if not v_owns then raise exception 'not_your_store'; end if;
  if v_order.status <> 'pending' then raise exception 'order_not_pending'; end if;

  update public.orders
     set status = 'preparing', accepted_at = now(),
         prep_minutes = coalesce(p_prep_minutes, prep_minutes)
   where id = p_order_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

create or replace function public.merchant_reject_order(p_order_id uuid, p_merchant_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_order public.orders%rowtype; v_owns boolean; v_rows int;
  v_merchant_variants text[] := array[
    p_merchant_phone,
    case when p_merchant_phone like '+20%' then '0'||substr(p_merchant_phone,4) else p_merchant_phone end,
    case when p_merchant_phone like '0%'   then '+2'||p_merchant_phone           else p_merchant_phone end
  ];
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'order_not_found'; end if;

  select exists(select 1 from public.stores where id = v_order.store_id and owner_phone = any(v_merchant_variants)) into v_owns;
  if not v_owns then raise exception 'not_your_store'; end if;
  if v_order.status not in ('pending', 'preparing') then raise exception 'order_not_rejectable'; end if;

  update public.orders set status = 'rejected', rejected_at = now() where id = p_order_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

create or replace function public.merchant_mark_order_ready(p_order_id uuid, p_merchant_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_order public.orders%rowtype; v_owns boolean; v_rows int;
  v_merchant_variants text[] := array[
    p_merchant_phone,
    case when p_merchant_phone like '+20%' then '0'||substr(p_merchant_phone,4) else p_merchant_phone end,
    case when p_merchant_phone like '0%'   then '+2'||p_merchant_phone           else p_merchant_phone end
  ];
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'order_not_found'; end if;

  select exists(select 1 from public.stores where id = v_order.store_id and owner_phone = any(v_merchant_variants)) into v_owns;
  if not v_owns then raise exception 'not_your_store'; end if;

  update public.orders set ready_at = now() where id = p_order_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

create or replace function public.confirm_order_delivery(p_order_id text, p_otp text, p_driver_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_rows int;
  v_driver_variants text[] := array[
    p_driver_phone,
    case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
    case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end
  ];
begin
  update public.orders
    set status = 'delivered', delivered_at = now()
  where id = p_order_id::uuid
    and driver_phone = any(v_driver_variants)
    and delivery_otp = p_otp
    and status <> 'delivered';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
