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
  select coalesce(jsonb_agg(o), '[]'::jsonb) into v_result
  from (
    select
      d.id as offer_id,
      d.target_type,
      d.expires_at,
      case when d.target_type = 'ride'
        then (select to_jsonb(r) from public.rides  r where r.id = d.target_id)
        else (select to_jsonb(o) from public.orders o where o.id = d.target_id)
      end as data
    from public.dispatch_offers d
    where d.driver_phone = p_driver_phone
      and d.status = 'pending'
      and d.expires_at > now()
    order by d.offered_at desc
  ) o
  where o.data is not null;

  return v_result;
end;
$$;

revoke all on function public.get_my_pending_offers(text) from public;
grant execute on function public.get_my_pending_offers(text) to anon, authenticated;
