-- =====================================================================
--  وصّلها — Security #23: إصلاح مقارنة uuid/text في دوال جلب العروض
--
--  نفس علة confirm_order_delivery (security-20): orders.id نوعه uuid،
--  و dispatch_offers.target_id نوعه text — أي مقارنة مباشرة بينهم بترمي
--  "operator does not exist: uuid = text". العلة دي كانت موجودة من زمان
--  في get_my_pending_offer/get_my_pending_offers بس، مش في
--  accept_dispatch_offer (ده اتصلح فعلاً في security-15 وبعديها
--  بـ ::text cast) — ما ظهرتش هنا قبل كده لأن طلبات التوصيل (orders)
--  ما كانتش بتوصل لمرحلة الديسباتش أصلاً (كان ناقصها store_lat/
--  store_lng — اتصلح في commit سابق). دلوقتي بقت طلبات فعلية بتوصل،
--  فالعلة ظهرت. الإصلاح: تحويل الطرفين لـ text قبل المقارنة (يشتغل
--  صح سواء كان العمود uuid أو text أصلاً، بدل ما نفترض نوعه).
--
--  ⚠️ الملف ده عمدًا مايلمسش accept_dispatch_offer — نسخته الحالية
--  (security-15) فيها فحوصات مهمة (نوع السيارة/الفئة/اعتماد السائق)
--  اتراكمت عبر أكتر من ملف؛ إعادة تعريفها هنا بنسخة أقدم هتمسحها.
--
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ── 1) get_my_pending_offer (مفرد) ──
create or replace function public.get_my_pending_offer(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer public.dispatch_offers;
  v_data  jsonb;
begin
  select * into v_offer
  from public.dispatch_offers
  where driver_phone = p_driver_phone
    and status = 'pending'
    and expires_at > now()
  order by offered_at desc
  limit 1;

  if not found then return null; end if;

  if v_offer.target_type = 'ride' then
    select to_jsonb(r) into v_data from public.rides r where r.id::text = v_offer.target_id;
  else
    select to_jsonb(o) into v_data from public.orders o where o.id::text = v_offer.target_id;
  end if;

  if v_data is null then return null; end if;

  return jsonb_build_object(
    'offer_id',    v_offer.id,
    'target_type', v_offer.target_type,
    'expires_at',  v_offer.expires_at,
    'data',        v_data
  );
end;
$$;

revoke all on function public.get_my_pending_offer(text) from public;
grant execute on function public.get_my_pending_offer(text) to anon, authenticated;

-- ── 2) get_my_pending_offers (جمع — security-22) ──
create or replace function public.get_my_pending_offers(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'offer_id', d.id,
        'target_type', d.target_type,
        'expires_at', d.expires_at,
        'data', case when d.target_type = 'ride' then to_jsonb(r) else to_jsonb(ord) end
      )
      order by d.offered_at desc
    ),
    '[]'::jsonb
  ) into v_result
  from public.dispatch_offers d
  left join public.rides  r   on d.target_type = 'ride'  and r.id::text = d.target_id
  left join public.orders ord on d.target_type = 'order' and ord.id::text = d.target_id
  where d.driver_phone = p_driver_phone
    and d.status = 'pending'
    and d.expires_at > now()
    and ((d.target_type = 'ride' and r.id is not null) or (d.target_type = 'order' and ord.id is not null));

  return v_result;
end;
$$;

revoke all on function public.get_my_pending_offers(text) from public;
grant execute on function public.get_my_pending_offers(text) to anon, authenticated;
