-- =====================================================================
--  وصّلها — Security #22: قائمة عروض متعددة للسائق بدل عرض واحد بس
--
--  get_my_pending_offer (مفرد) كان بيرجّع أحدث عرض pending واحد بس
--  (limit 1) — فلو وصل للسائق أكتر من عرض في نفس الوقت (بعد ما بقى
--  يقدر يقبل أكتر من شغلانة مع بعض)، مكنش يشوفهم كلهم. الدالة الجديدة
--  دي بترجع كل العروض الـ pending للسائق كـ jsonb array، عشان التطبيق
--  يعرضهم كقائمة بدل نافذة واحدة بس.
--
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.get_my_pending_offers(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  -- Explicit LEFT JOINs + jsonb_build_object instead of a per-row
  -- correlated subquery inside a CASE — functionally the same lookup as
  -- get_my_pending_offer (singular), just aggregated instead of limit-1'd.
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
  left join public.rides  r   on d.target_type = 'ride'  and r.id = d.target_id
  left join public.orders ord on d.target_type = 'order' and ord.id = d.target_id
  where d.driver_phone = p_driver_phone
    and d.status = 'pending'
    and d.expires_at > now()
    and ((d.target_type = 'ride' and r.id is not null) or (d.target_type = 'order' and ord.id is not null));

  return v_result;
end;
$$;

revoke all on function public.get_my_pending_offers(text) from public;
grant execute on function public.get_my_pending_offers(text) to anon, authenticated;
