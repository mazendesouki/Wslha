-- =====================================================================
--  وصّلها — Security #75: نظام كوبونات وخصومات
--
--  الأدمن بيعمل كود خصم (نسبة أو مبلغ ثابت) من لوحة التحكم، والعميل
--  بيدخله قبل تأكيد الحجز/الطلب.
--
--  قرار معماري مهم: fare عمود rides بيتحسب/يتراجع تلقائيًا في INSERT
--  عن طريق trigger (guard_ride_fare — security-11/29/35/55/58/60/61/62)
--  بيعيد حساب السعر من distance_km + to_area/الفئة، وبيتجاهل أي قيمة
--  fare جاية من العميل. تعديل الـ trigger ده عشان يطرح خصم فيه مخاطرة
--  عالية على منطق تسعير حساس اتلمس في 9 migrations قبل كده.
--
--  فالحل الأأمن: الخصم بيتطبق كـ "استرداد" (cashback) لمحفظة العميل —
--  العميل بيحجز ويدفع السعر الكامل زي العادي، وبعد إتمام الحجز/الطلب
--  بننزّل قيمة الخصم في محفظته فورًا كـ wallet_transactions (نفس نمط
--  no_show_compensation في security-70 بالظبط). النتيجة الفعلية للعميل
--  واحدة (دفع أقل بالصافي)، من غير أي لمسة لمنطق حساب fare نفسه.
--
--  الجداول:
--   - coupons: تعريف الكود (نوع الخصم/قيمته/سقفه/الحد الأدنى للطلب/
--     حد الاستخدام الكلي وللمستخدم الواحد/نوع الخدمة المستهدفة/الصلاحية).
--   - coupon_redemptions: سجل كل استخدام (يمنع تكرار الاستخدام لنفس
--     الرحلة/الطلب ولاحترام الحدود).
--
--  زي كل جدول حساس تاني في المشروع (accounts/wallets/...): مفيش أي
--  قراءة/كتابة مباشرة — كل حاجة عن طريق دوال:
--   - validate_coupon(code, phone, amount, service_type) → معاينة الخصم
--     قبل الدفع (بيتنادى من شاشة الحجز نفسها، مايحجزش استخدام).
--   - redeem_coupon(code, phone, amount, service_type, reference_id) →
--     يتنادى بعد ما الرحلة/الطلب يتعمل فعلاً، بيسجل الاستخدام ويحوّل
--     الخصم لمحفظة العميل فورًا.
--   - admin_create_coupon / admin_list_coupons / admin_set_coupon_active
--     (بباسورد الأدمن زي admin_list_accounts).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  discount_type text not null check (discount_type in ('percent', 'fixed')),
  discount_value numeric not null check (discount_value > 0),
  max_discount numeric,
  min_amount numeric not null default 0,
  usage_limit int,
  per_user_limit int not null default 1,
  applies_to text not null default 'all' check (applies_to in ('ride', 'delivery', 'all')),
  active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons(id) on delete cascade,
  phone text not null,
  service_type text not null,
  reference_id text not null,
  discount_amount numeric not null,
  created_at timestamptz not null default now(),
  unique (service_type, reference_id)
);

alter table public.coupons enable row level security;
alter table public.coupon_redemptions enable row level security;
revoke all on public.coupons from anon, authenticated;
revoke all on public.coupon_redemptions from anon, authenticated;

-- ---------------------------------------------------------------------
-- الحساب المشترك بين validate_coupon و redeem_coupon (نفس منطق التحقق
-- بالظبط في المكانين عشان معاينة الخصم قبل الحجز تطابق اللي هيتطبق فعليًا).
-- ---------------------------------------------------------------------
create or replace function public._check_coupon(
  p_code text, p_phone text, p_amount numeric, p_service_type text
) returns table(ok boolean, coupon_id uuid, discount_amount numeric, message text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_c record; v_uses int; v_user_uses int; v_discount numeric;
begin
  select * into v_c from public.coupons where upper(code) = upper(trim(p_code));
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

  select count(*) into v_uses from public.coupon_redemptions where coupon_id = v_c.id;
  if v_c.usage_limit is not null and v_uses >= v_c.usage_limit then
    return query select false, v_c.id, 0::numeric, 'الكود خلص من الاستخدام'; return;
  end if;

  select count(*) into v_user_uses from public.coupon_redemptions where coupon_id = v_c.id and phone = p_phone;
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

create or replace function public.validate_coupon(p_code text, p_phone text, p_amount numeric, p_service_type text)
returns table(valid boolean, discount_amount numeric, message text)
language sql
security definer
set search_path = public, extensions
as $$
  select ok, discount_amount, message from public._check_coupon(p_code, p_phone, p_amount, p_service_type);
$$;
grant execute on function public.validate_coupon(text, text, numeric, text) to anon, authenticated;

create or replace function public.redeem_coupon(
  p_code text, p_phone text, p_amount numeric, p_service_type text, p_reference_id text
) returns numeric
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_check record;
begin
  if exists (select 1 from public.coupon_redemptions where service_type = p_service_type and reference_id = p_reference_id) then
    raise exception 'already_redeemed_for_this_trip';
  end if;

  select * into v_check from public._check_coupon(p_code, p_phone, p_amount, p_service_type);
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
grant execute on function public.redeem_coupon(text, text, numeric, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- دوال الأدمن — إنشاء/عرض/تفعيل-تعطيل، بباسورد زي admin_list_accounts.
-- ---------------------------------------------------------------------
create or replace function public.admin_create_coupon(
  p_admin_phone text, p_admin_password text, p_code text, p_discount_type text,
  p_discount_value numeric, p_max_discount numeric, p_min_amount numeric,
  p_usage_limit int, p_per_user_limit int, p_applies_to text, p_expires_at timestamptz
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

  insert into public.coupons (code, discount_type, discount_value, max_discount, min_amount, usage_limit, per_user_limit, applies_to, expires_at)
  values (upper(trim(p_code)), p_discount_type, p_discount_value, p_max_discount, coalesce(p_min_amount, 0),
          p_usage_limit, coalesce(p_per_user_limit, 1), coalesce(p_applies_to, 'all'), p_expires_at);
  return true;
exception when unique_violation then
  return false;
end;
$$;
grant execute on function public.admin_create_coupon(text, text, text, text, numeric, numeric, numeric, int, int, text, timestamptz) to anon, authenticated;

create or replace function public.admin_list_coupons(p_admin_phone text, p_admin_password text)
returns table(
  id uuid, code text, discount_type text, discount_value numeric, max_discount numeric,
  min_amount numeric, usage_limit int, per_user_limit int, applies_to text, active boolean,
  expires_at timestamptz, created_at timestamptz, times_used bigint
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
           (select count(*) from public.coupon_redemptions r where r.coupon_id = c.id)
      from public.coupons c
     order by c.created_at desc limit 500;
end;
$$;
grant execute on function public.admin_list_coupons(text, text) to anon, authenticated;

create or replace function public.admin_set_coupon_active(p_admin_phone text, p_admin_password text, p_coupon_id uuid, p_active boolean)
returns boolean
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

  update public.coupons set active = p_active where id = p_coupon_id;
  return true;
end;
$$;
grant execute on function public.admin_set_coupon_active(text, text, uuid, boolean) to anon, authenticated;

-- زي كل ميزة قبل كده — قابلة للإيقاف الكامل من لوحة التحكم.
insert into public.app_settings (key, value) values
  ('feature_coupons_enabled', 'true')
on conflict (key) do nothing;
