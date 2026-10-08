-- =====================================================================
--  وصّلها — Security #118: إصلاح ثغرة أمنية في redeem_coupon
--
--  redeem_coupon (security-75) من الدوال اللي anon يقدر ينادي عليها
--  مباشرة (REST RPC)، وكانت بتثق بالكامل في p_amount و p_reference_id
--  الجايين من العميل من غير أي تحقق:
--    - p_amount: أي رقم يبعته العميل كان بيُستخدم كـ"قيمة الطلب" لحساب
--      الخصم — يعني ممكن حد يبعت p_amount كبير يفضي لأقصى خصم (حتى سقف
--      max_discount) من غير أي علاقة بسعر رحلة/طلب حقيقي.
--    - p_reference_id: نص حر، مفيش تحقق إنه ID رحلة/طلب حقيقي أصلاً،
--      ولا إنه تابع لـ p_phone المبعوت. يعني حد يقدر يخترع reference_id
--      جديد كل مرة (usage_limit/per_user_limit بس اللي بيوقفوه) ويكسب
--      cashback حقيقي في محفظته من غير أي رحلة/طلب حصل فعلاً.
--
--  الإصلاح (بدون تغيير توقيع الدالة ولا الحاجة لأي تعديل في التطبيق):
--  redeem_coupon بقى يجيب المبلغ الحقيقي (fare/total) ويتأكد من ملكية
--  الرحلة/الطلب (customer_phone) من جدول rides/orders نفسه — p_amount
--  الجاي من العميل بقى متجاهَل تمامًا في حساب الخصم، موجود بس في
--  التوقيع للتوافق مع الكود الحالي في التطبيق (coupon_repository.dart).
--
--  validate_coupon من غير تغيير — دالة معاينة بس من غير أي أثر جانبي
--  (مفيش wallet credit)، فمفيش فيها نفس المخاطرة.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

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
  if exists (select 1 from public.coupon_redemptions where service_type = p_service_type and reference_id = p_reference_id) then
    raise exception 'already_redeemed_for_this_trip';
  end if;

  begin
    v_ref_uuid := p_reference_id::uuid;
  exception when invalid_text_representation then
    raise exception 'مرجع العملية غير صالح';
  end;

  -- v_real_amount هو المصدر الوحيد لقيمة الطلب دلوقتي — p_amount (معامل
  -- الدالة) ما بقى يُستخدم في أي حساب خصم من هنا تحت.
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

grant execute on function public.redeem_coupon(text, text, numeric, text, text) to anon, authenticated;
