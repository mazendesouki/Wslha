-- =====================================================================
--  وصّلها — Security #105: كوبون خصم تلقائي لأول رحلة/طلب لأي عميل جديد
--
--  نظام الكوبونات الموجود (security-75) كله يدوي: العميل لازم يكتب
--  كود. هنا بنضيف مفتاح على أي كوبون "auto_apply_first_order" — لو
--  الأدمن فعّله على كوبون معين، وده أول رحلة/طلب فعلي للعميل ده على
--  الإطلاق (مفيش أي رحلة أو طلب سابق بأي حالة)، الخصم بيتطبّق تلقائيًا
--  كـ cashback لمحفظته بمجرد إنشاء الرحلة/الطلب — من غير ما يكتب حاجة،
--  بنفس آلية الاسترداد الآمنة اللي security-75 وضّح سبب استخدامها
--  (عمود fare/total نفسه ميتلمسش).
--
--  التنفيذ عن طريق AFTER INSERT triggers على rides و orders — يعني
--  شغال مهما كانت الشاشة اللي الرحلة/الطلب اتعمل منها (مافيش أي تعديل
--  مطلوب في تطبيق الموبايل أو الويب).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.coupons add column if not exists auto_apply_first_order boolean not null default false;

-- ---------------------------------------------------------------------
-- منطق مشترك: لو ده فعلاً أول رحلة/طلب للعميل، ولقينا كوبون مفعّل
-- auto_apply_first_order صالح، يتطبق تلقائيًا (نفس منطق _check_coupon
-- + redeem_coupon في security-75، لكن الكوبون معروف مسبقًا مش بكود).
-- ---------------------------------------------------------------------
create or replace function public._apply_first_order_coupon(
  p_phone text, p_service_type text, p_reference_id text, p_amount numeric
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_prior_count int;
  v_c record;
  v_uses int;
  v_discount numeric;
begin
  if p_phone is null or p_amount is null or p_amount <= 0 then return; end if;

  select
    (select count(*) from public.rides  where customer_phone = p_phone and id::text <> p_reference_id) +
    (select count(*) from public.orders where customer_phone = p_phone and id::text <> p_reference_id)
  into v_prior_count;
  if v_prior_count > 0 then return; end if; -- مش أول رحلة/طلب

  select * into v_c from public.coupons
   where active and auto_apply_first_order
     and (expires_at is null or expires_at > now())
     and (applies_to = 'all' or applies_to = p_service_type)
     and min_amount <= p_amount
   order by created_at asc
   limit 1;
  if v_c.id is null then return; end if;

  select count(*) into v_uses from public.coupon_redemptions r where r.coupon_id = v_c.id;
  if v_c.usage_limit is not null and v_uses >= v_c.usage_limit then return; end if;

  if v_c.discount_type = 'percent' then
    v_discount := p_amount * v_c.discount_value / 100.0;
    if v_c.max_discount is not null then v_discount := least(v_discount, v_c.max_discount); end if;
  else
    v_discount := v_c.discount_value;
  end if;
  v_discount := least(v_discount, p_amount);
  v_discount := round(v_discount, 2);
  if v_discount <= 0 then return; end if;

  insert into public.coupon_redemptions (coupon_id, phone, service_type, reference_id, discount_amount)
  values (v_c.id, p_phone, p_service_type, p_reference_id, v_discount)
  on conflict (service_type, reference_id) do nothing;
  if not found then return; end if;

  perform public.add_wallet_balance(p_phone, v_discount);
  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'wtx-coupon-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    p_phone, v_discount, 'coupon_discount', p_reference_id,
    'خصم ترحيبي تلقائي (' || v_c.code || ') لأول رحلة/طلب', now()
  );
exception when unique_violation then
  return; -- تعارض نادر (نفس المرجع اتعالج بالتوازي) — تجاهل بأمان
end;
$$;

create or replace function public._trg_first_order_coupon_ride()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public._apply_first_order_coupon(new.customer_phone, 'ride', new.id::text, new.fare);
  return new;
end;
$$;

drop trigger if exists trg_first_order_coupon_ride on public.rides;
create trigger trg_first_order_coupon_ride
  after insert on public.rides
  for each row execute function public._trg_first_order_coupon_ride();

create or replace function public._trg_first_order_coupon_order()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public._apply_first_order_coupon(new.customer_phone, 'delivery', new.id::text, new.total);
  return new;
end;
$$;

drop trigger if exists trg_first_order_coupon_order on public.orders;
create trigger trg_first_order_coupon_order
  after insert on public.orders
  for each row execute function public._trg_first_order_coupon_order();

-- ---------------------------------------------------------------------
-- تحديث دوال الأدمن عشان تدعم المفتاح الجديد.
-- ---------------------------------------------------------------------
create or replace function public.admin_create_coupon(
  p_admin_phone text, p_admin_password text, p_code text, p_discount_type text,
  p_discount_value numeric, p_max_discount numeric, p_min_amount numeric,
  p_usage_limit int, p_per_user_limit int, p_applies_to text, p_expires_at timestamptz,
  p_auto_apply_first_order boolean default false
) returns boolean
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
  if v_admin.phone is null then return false; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;

  insert into public.coupons (code, discount_type, discount_value, max_discount, min_amount, usage_limit, per_user_limit, applies_to, expires_at, auto_apply_first_order)
  values (upper(trim(p_code)), p_discount_type, p_discount_value, p_max_discount, coalesce(p_min_amount, 0),
          p_usage_limit, coalesce(p_per_user_limit, 1), coalesce(p_applies_to, 'all'), p_expires_at, coalesce(p_auto_apply_first_order, false));
  return true;
exception when unique_violation then
  return false;
end;
$$;
grant execute on function public.admin_create_coupon(text, text, text, text, numeric, numeric, numeric, int, int, text, timestamptz, boolean) to anon, authenticated;

create or replace function public.admin_list_coupons(p_admin_phone text, p_admin_password text)
returns table(
  id uuid, code text, discount_type text, discount_value numeric, max_discount numeric,
  min_amount numeric, usage_limit int, per_user_limit int, applies_to text, active boolean,
  expires_at timestamptz, created_at timestamptz, times_used bigint, auto_apply_first_order boolean
)
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

  return query
    select c.id, c.code, c.discount_type, c.discount_value, c.max_discount, c.min_amount,
           c.usage_limit, c.per_user_limit, c.applies_to, c.active, c.expires_at, c.created_at,
           (select count(*) from public.coupon_redemptions r where r.coupon_id = c.id),
           c.auto_apply_first_order
      from public.coupons c
     order by c.created_at desc limit 500;
end;
$$;
grant execute on function public.admin_list_coupons(text, text) to anon, authenticated;
