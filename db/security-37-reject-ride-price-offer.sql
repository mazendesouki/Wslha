-- =====================================================================
--  وصّلها — Security #37: رفض عرض سعر منفرد (تفاوض الرحلات)
--
--  العميل كان بيشوف زرار "قبول" بس على كل عرض سعر، من غير أي زرار
--  "رفض" — الإضافة دي بتدّيه خيار يتجاهل عرض معيّن (يختفي من قائمته
--  هو بس) ويفضل مستني باقي العروض أو عروض جديدة، بدل ما يبقى مضطر
--  يقبل أول عرض يشوفه.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.reject_ride_price_offer(
  p_ride_id uuid, p_offer_id uuid, p_customer_phone text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_ride record; v_rows int;
begin
  select * into v_ride from public.rides where id = p_ride_id;
  if v_ride.id is null then raise exception 'ride_not_found'; end if;

  if v_ride.customer_phone not in (
       p_customer_phone,
       case when p_customer_phone like '+20%' then '0'||substr(p_customer_phone,4) else p_customer_phone end,
       case when p_customer_phone like '0%'   then '+2'||p_customer_phone           else p_customer_phone end
     ) then
    raise exception 'not_your_ride';
  end if;

  update public.ride_price_offers
     set status = 'rejected'
   where id = p_offer_id and ride_id = p_ride_id and status = 'pending';
  get diagnostics v_rows = row_count;

  return v_rows > 0;
end;
$$;
grant execute on function public.reject_ride_price_offer(uuid, uuid, text) to anon, authenticated;
