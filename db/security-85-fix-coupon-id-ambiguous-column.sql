-- =====================================================================
--  وصّلها — Security #85: إصلاح باگ حقيقي في التحقق من الكوبون
--
--  _check_coupon كان بيرمي خطأ SQL "column reference coupon_id is
--  ambiguous" لأي كود صالح وفعّال وصل لمرحلة فحص عدد الاستخدامات —
--  لأن اسم عمود الإخراج (coupon_id) في RETURNS TABLE بيتعارض مع اسم
--  عمود جدول coupon_redemptions نفسه، فـ PostgreSQL ما عرفش يفرّق
--  بينهم في شرط WHERE. الكوبونات القديمة اللي اتجرّبت قبل كده
--  (WELCOME10/11) كانت بترفض قبل الوصول للسطر ده أصلاً (متوقفة، أو
--  فيها مسافة في الكود)، فالباگ ده ما ظهرش غير مع كود فعّال فعلاً.
--
--  الحل: تأهيل عمود الجدول بالاسم المستعار (r.coupon_id) بدل الاسم
--  المجرّد في السطرين اللي بيستعلموا على coupon_redemptions.
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
