-- =====================================================================
--  وصّلها — Security #82: كود الكوبون بقى غير حساس للمسافات
--
--  اكتشفنا إن الأدمن كتب كود "WELCOME 11" (بمسافة في النص) من لوحة
--  التحكم، والعميل بيجرب "WELCOME11" (من غير مسافة) عند التفعيل —
--  مايتطابقوش فيفشل التفعيل بهدوء. الحل: المقارنة بقت بتشيل أي
--  مسافات من الكود المخزّن والكود المدخل قبل المقارنة، فالكود يشتغل
--  سواء اتكتب بمسافة أو من غيرها. الأكواد الموجودة بالفعل اتنضّفت.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public._check_coupon(
  p_code text, p_phone text, p_amount numeric, p_service_type text
) returns table(ok boolean, coupon_id uuid, discount_amount numeric, message text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_c record; v_uses int; v_user_uses int; v_discount numeric;
begin
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
  values (upper(replace(trim(p_code), ' ', '')), p_discount_type, p_discount_value, p_max_discount, coalesce(p_min_amount, 0),
          p_usage_limit, coalesce(p_per_user_limit, 1), coalesce(p_applies_to, 'all'), p_expires_at);
  return true;
exception when unique_violation then
  return false;
end;
$$;

update public.coupons set code = upper(replace(code, ' ', '')) where code ~ ' ';
