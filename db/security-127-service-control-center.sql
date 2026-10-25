-- =====================================================================
--  وصّلها — Security #127: مركز التحكم في الخدمات (Service Control Center)
--
--  الأدمن طلب تحكم مركزي في كل "خدمة" كبيرة بالتطبيق — تشغيل دايم،
--  إيقاف دايم، أو تشغيل مؤقت لفترة محددة (مفيد خصوصًا وقت الإطلاق
--  الرسمي: تقفل كل حاجة وتسيب خدمة واحدة بس شغالة).
--
--  النظام القديم (feature_*_enabled في app_settings، security-72
--  وغيره) كان بيخفي الميزة من واجهة التطبيق بس — مفيش أي تحقق فعلي في
--  السيرفر، فحد يقدر يتحايل ويكلم الـ API مباشرة حتى لو "مقفول" من
--  الواجهة. النظام ده مختلف: كل خدمة بتتفحص فعليًا جوه نفس نقطة إنشاء
--  الصف (trigger قبل INSERT، أو أول سطر في دالة الإنشاء) — رفض حقيقي
--  من قاعدة البيانات نفسها، مش مجرد إخفاء زرار.
--
--  الخدمات المغطاة (10): رحلات عادي/خارجي/مطار، طلبات توصيل، سوق
--  مستعمل، عقود شركات، تسجيل سائقين جدد، تسجيل تجار جدد، إيداع محفظة،
--  كوبونات. كل خدمة ليها trigger/فحص مستقل عن منطق التسعير/التحقق
--  الموجود أصلاً — إضافة جنب الموجود، مش تعديل فيه، عشان نقلل مخاطر
--  كسر أي حاجة شغالة.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) الجدول + الدالة المركزية اللي كل نقطة فحص بتنادي عليها.
-- ---------------------------------------------------------------------
create table if not exists public.service_controls (
  service_key text primary key,
  label_ar text not null,
  status text not null default 'on' check (status in ('on', 'off', 'scheduled')),
  scheduled_start timestamptz,
  scheduled_end timestamptz,
  updated_by text,
  updated_at timestamptz not null default now()
);
revoke all on public.service_controls from anon, authenticated;

insert into public.service_controls (service_key, label_ar) values
  ('rides_local',          'الرحلات داخل المدينة'),
  ('rides_external',       'الرحلات الخارجية'),
  ('rides_airport',        'رحلات المطار'),
  ('delivery_orders',      'طلبات التوصيل'),
  ('marketplace',          'السوق المستعمل'),
  ('corporate',            'طلبات عقود الشركات'),
  ('driver_registration',  'تسجيل سائقين جدد'),
  ('merchant_registration','تسجيل تجار جدد'),
  ('wallet_deposit',       'إيداع المحفظة'),
  ('coupons',              'كوبونات الخصم')
on conflict (service_key) do nothing;

-- صف غير موجود (خدمة مستقبلية محدش عرّفها هنا) = شغالة افتراضيًا، نفس
-- مبدأ fail-open اللي core/feature_flags.dart الفلاتر بيستخدمه أصلًا.
create or replace function public.is_service_active(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(
    (select case s.status
       when 'on' then true
       when 'off' then false
       when 'scheduled' then
         now() >= s.scheduled_start and (s.scheduled_end is null or now() <= s.scheduled_end)
     end
     from public.service_controls s where s.service_key = p_key),
    true
  );
$$;
grant execute on function public.is_service_active(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) دوال الأدمن — نفس نمط admin_list_coupons/admin_set_coupon_active.
-- ---------------------------------------------------------------------
create or replace function public.admin_list_service_controls(p_admin_phone text, p_admin_password text)
returns setof public.service_controls
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return;
  end if;

  return query select * from public.service_controls order by service_key;
end;
$$;
grant execute on function public.admin_list_service_controls(text, text) to anon, authenticated;

create or replace function public.admin_set_service_control(
  p_admin_phone text, p_admin_password text, p_service_key text, p_status text,
  p_scheduled_start timestamptz default null, p_scheduled_end timestamptz default null
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_status not in ('on', 'off', 'scheduled') then
    raise exception 'invalid status: %', p_status;
  end if;
  if p_status = 'scheduled' and p_scheduled_start is null then
    raise exception 'scheduled status needs a start time';
  end if;

  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return false; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;

  update public.service_controls
     set status = p_status, scheduled_start = p_scheduled_start, scheduled_end = p_scheduled_end,
         updated_by = v_admin.phone, updated_at = now()
   where service_key = p_service_key;
  return found;
end;
$$;
grant execute on function public.admin_set_service_control(text, text, text, text, timestamptz, timestamptz) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) نقاط الفحص الفعلية — Triggers/فحوصات مستقلة، منفصلة عن منطق
--    التسعير/التحقق الموجود أصلاً (مفيش تعديل في أي trigger قديم).
-- ---------------------------------------------------------------------

-- 3.1 الرحلات (محلي/خارجي/مطار) — حسب ride_type.
create or replace function public._guard_ride_service_control()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_key text;
begin
  v_key := case new.ride_type
    when 'external' then 'rides_external'
    when 'airport'   then 'rides_airport'
    else 'rides_local'
  end;
  if not public.is_service_active(v_key) then
    raise exception 'service_unavailable: %', v_key;
  end if;
  return new;
end;
$$;
create or replace trigger trg_guard_ride_service_control
  before insert on public.rides
  for each row execute function public._guard_ride_service_control();

-- 3.2 طلبات التوصيل (كل الأنواع — متجر/دليفري عام/تاجر).
create or replace function public._guard_order_service_control()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_service_active('delivery_orders') then
    raise exception 'service_unavailable: delivery_orders';
  end if;
  return new;
end;
$$;
create or replace trigger trg_guard_order_service_control
  before insert on public.orders
  for each row execute function public._guard_order_service_control();

-- 3.3 عقود الشركات — الجدول اتعمل يدوي على لوحة Supabase من غير أي
--     migration متوافقة (business.astro بتكتب فيه مباشرة بالـ anon
--     key)، فالـ trigger ده أول تحكم سيرفري عليه خالص.
create or replace function public._guard_corporate_service_control()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_service_active('corporate') then
    raise exception 'service_unavailable: corporate';
  end if;
  return new;
end;
$$;
create or replace trigger trg_guard_corporate_service_control
  before insert on public.corporate_contracts
  for each row execute function public._guard_corporate_service_control();

-- 3.4 تسجيل سائقين/تجار جدد — على INSERT بس (مش UPDATE)، عشان متعاملش
--     مع متقدّمين موجودين فعلاً بيكملوا/يعدّلوا بياناتهم.
create or replace function public._guard_driver_registration_open()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_service_active('driver_registration') then
    raise exception 'service_unavailable: driver_registration';
  end if;
  return new;
end;
$$;
create or replace trigger trg_guard_driver_registration_open
  before insert on public.driver_applications
  for each row execute function public._guard_driver_registration_open();

create or replace function public._guard_merchant_registration_open()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_service_active('merchant_registration') then
    raise exception 'service_unavailable: merchant_registration';
  end if;
  return new;
end;
$$;
create or replace trigger trg_guard_merchant_registration_open
  before insert on public.merchant_applications
  for each row execute function public._guard_merchant_registration_open();

-- 3.5 السوق المستعمل — جوه request_marketplace_delivery نفسها
--     (الجدول مقفول تمامًا، مفيش INSERT مباشر ينفع له trigger).
create or replace function public.request_marketplace_delivery(
  p_item_id text, p_buyer_phone text, p_buyer_name text, p_buyer_address text, p_shipment_type text default null
) returns public.marketplace_orders
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
  v_shipment_label text;
begin
  if not public.is_service_active('marketplace') then
    raise exception 'service_unavailable: marketplace';
  end if;

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
$$;

-- 3.6 إيداع المحفظة.
create or replace function public.request_deposit(
  p_phone text, p_amount numeric, p_method text default null, p_note text default null
) returns public.wallet_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_row public.wallet_requests;
begin
  if not public.is_service_active('wallet_deposit') then
    raise exception 'service_unavailable: wallet_deposit';
  end if;
  if p_amount is null or p_amount < 10 then
    raise exception 'amount_too_small';
  end if;
  insert into public.wallet_requests (id, phone, kind, amount, method, note)
  values ('dep-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,6),
          p_phone, 'deposit', round(p_amount::numeric, 2), p_method, p_note)
  returning * into v_row;
  return v_row;
end;
$$;

-- 3.7 الكوبونات — redeem (فعلي) + _check_coupon (معاينة، عشان الرسالة
--     تتسق مع الاستخدام الفعلي).
create or replace function public._check_coupon(
  p_code text, p_phone text, p_amount numeric, p_service_type text
) returns table(ok boolean, coupon_id uuid, discount_amount numeric, message text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_c record; v_uses int; v_user_uses int; v_discount numeric;
begin
  if not public.is_service_active('coupons') then
    return query select false, null::uuid, 0::numeric, 'خدمة الكوبونات متوقفة مؤقتًا'; return;
  end if;

  select * into v_c from public.coupons
   where upper(replace(code, ' ', '')) = upper(replace(trim(p_code), ' ', ''));
  if v_c.id is null then return query select false, null::uuid, 0::numeric, 'كود غير موجود'; return; end if;
  if not v_c.active then return query select false, v_c.id, 0::numeric, 'الكود متوقف'; return; end if;
  if v_c.expires_at is not null and v_c.expires_at < now() then
    return query select false, v_c.id, 0::numeric, 'انتهت صلاحية الكود'; return;
  end if;
  if v_c.applies_to <> 'all' and v_c.applies_to <> p_service_type then
    return query select false, v_c.id, 0::numeric, 'الكود مش صالح للخدمة دي'; return;
  end if;
  if p_amount < v_c.min_amount then
    return query select false, v_c.id, 0::numeric, 'الحد الأدنى للطلب ' || v_c.min_amount || ' ج.م'; return;
  end if;

  select count(*) into v_uses from public.coupon_redemptions r where r.coupon_id = v_c.id;
  if v_c.usage_limit is not null and v_uses >= v_c.usage_limit then
    return query select false, v_c.id, 0::numeric, 'الكود خلص من الاستخدام'; return;
  end if;

  select count(*) into v_user_uses from public.coupon_redemptions r where r.coupon_id = v_c.id and r.phone = p_phone;
  if v_user_uses >= v_c.per_user_limit then
    return query select false, v_c.id, 0::numeric, 'استخدمت الكود ده قبل كده'; return;
  end if;

  if v_c.discount_type = 'percent' then
    v_discount := p_amount * v_c.discount_value / 100.0;
    if v_c.max_discount is not null then v_discount := least(v_discount, v_c.max_discount); end if;
  else
    v_discount := v_c.discount_value;
  end if;
  v_discount := least(v_discount, p_amount);

  return query select true, v_c.id, round(v_discount, 2), 'الكود صالح';
end;
$$;

create or replace function public.redeem_coupon(
  p_code text, p_phone text, p_amount numeric, p_service_type text, p_reference_id text
) returns numeric
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_check record;
  v_real_amount numeric;
  v_owner text;
  v_ref_uuid uuid;
begin
  if not public.is_service_active('coupons') then
    raise exception 'service_unavailable: coupons';
  end if;

  if exists (select 1 from public.coupon_redemptions where service_type = p_service_type and reference_id = p_reference_id) then
    raise exception 'already_redeemed_for_this_trip';
  end if;

  begin
    v_ref_uuid := p_reference_id::uuid;
  exception when invalid_text_representation then
    raise exception 'مرجع العملية غير صالح';
  end;

  if p_service_type = 'ride' then
    select fare::numeric, customer_phone into v_real_amount, v_owner from public.rides where id = v_ref_uuid;
  elsif p_service_type = 'delivery' then
    select total, customer_phone into v_real_amount, v_owner from public.orders where id = v_ref_uuid;
  else
    raise exception 'نوع خدمة غير معروف: %', p_service_type;
  end if;

  if v_owner is null then
    raise exception 'مرجع العملية غير موجود';
  end if;
  if v_owner <> p_phone then
    raise exception 'الرحلة/الطلب غير تابع لهذا الرقم';
  end if;

  select * into v_check from public._check_coupon(p_code, p_phone, v_real_amount, p_service_type);
  if not v_check.ok then raise exception '%', v_check.message; end if;

  insert into public.coupon_redemptions (coupon_id, phone, service_type, reference_id, discount_amount)
  values (v_check.coupon_id, p_phone, p_service_type, p_reference_id, v_check.discount_amount);

  perform public.add_wallet_balance(p_phone, v_check.discount_amount);
  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'wtx-coupon-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    p_phone, v_check.discount_amount, 'coupon_discount', p_reference_id,
    'خصم كود ' || upper(trim(p_code)), now()
  );

  return v_check.discount_amount;
end;
$$;
