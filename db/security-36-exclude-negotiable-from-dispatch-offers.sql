-- =====================================================================
--  وصّلها — Security #36: استبعاد الرحلات التفاوضية من عروض الديسباتش العادية
--
--  اكتُشف بعد تفعيل نظام التفاوض (security-35): محرك الديسباتش الخارجي
--  (server/index.js) بيسمع لأي رحلة جديدة status='pending' من غير سائق
--  — من غير ما يفرّق تفاوضية ولا لأ — فبيعمل dispatch_offers عادي
--  بالسعر الثابت لنفس الرحلة التفاوضية كمان. النتيجة: السائق كان شايف
--  "عرض عادي" بالسعر الثابت جنب "طلب تفاوض" لنفس الرحلة، ولو قبل
--  العرض العادي، الرحلة تتقفل فورًا بالسعر القديم وتختفي من قائمة
--  التفاوض (تجاوز كامل لنظام العروض).
--
--  الإصلاح هنا على مستوى الدالتين اللي تطبيق السائق بيستعلم بيهم كل 5
--  ثواني (get_my_pending_offer/get_my_pending_offers) — بتستبعد أي عرض
--  ديسباتش هدفه رحلة is_negotiable=true، حتى لو الخادم الخارجي لسه
--  بيعملها (هتفضل موجودة في dispatch_offers لكن مش هتظهر لأي سائق أبدًا،
--  فتنتهي صلاحيتها تلقائيًا بعد 30 ثانية من غير أي تأثير). ده إصلاح
--  فوري يشتغل من غير ما نحتاج نعيد نشر الخادم الخارجي.
--
--  ⚠️ عمدًا مش بيلمس accept_dispatch_offer (فيها فحوصات مهمة اتراكمت
--  عبر أكتر من ملف أمان — نفس تحذير security-23).
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
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
  v_ride_negotiable boolean;
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
    select to_jsonb(r), coalesce(r.is_negotiable, false) into v_data, v_ride_negotiable
    from public.rides r where r.id::text = v_offer.target_id;
    if v_ride_negotiable then return null; end if;
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

-- ── 2) get_my_pending_offers (جمع) ──
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
    and ((d.target_type = 'ride' and r.id is not null and coalesce(r.is_negotiable, false) = false)
         or (d.target_type = 'order' and ord.id is not null));

  return v_result;
end;
$$;

revoke all on function public.get_my_pending_offers(text) from public;
grant execute on function public.get_my_pending_offers(text) to anon, authenticated;
