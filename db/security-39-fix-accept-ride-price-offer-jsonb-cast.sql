-- =====================================================================
--  وصّلها — Security #39: تصحيح خطأ "invalid input syntax for type json"
--  عند قبول عرض سعر (accept_ride_price_offer)
--
--  السبب: v_updated معرّفة record، وبتتملى بـ
--  `returning to_jsonb(rides.*) into v_updated` — القيمة جوّاها فعلاً
--  jsonb سليم، بس الدالة بترجّعها بـ `return v_updated;` مباشرة رغم إن
--  نوع الإرجاع المُعلن هو jsonb. بوستجرس بيحوّل الـ record البرّاني لنص
--  على هيئة row-literal زي (val1,val2,...) الأول، وده اللي بيطلع منه
--  الخطأ "Token "(" is invalid" لما يحاول يفسّره كـ JSON. الحل: نلف
--  الإرجاع بـ to_jsonb() زي ما submit_ride_price_offer بتعمل بالظبط
--  (return to_jsonb(v_row);) بدل الإرجاع المباشر.
--
--  باقي منطق الدالة (فحص الملكية، حارس التزامن driver_phone is null،
--  تحديث حالة العروض) زي ما هو من غير أي تغيير.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.accept_ride_price_offer(
  p_ride_id uuid, p_offer_id uuid, p_customer_phone text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_ride record; v_offer record; v_updated record;
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

  select * into v_offer from public.ride_price_offers where id = p_offer_id and ride_id = p_ride_id;
  if v_offer.id is null then raise exception 'offer_not_found'; end if;
  if v_offer.status <> 'pending' then raise exception 'offer_no_longer_available'; end if;

  update public.rides
     set status = 'accepted',
         driver_phone = v_offer.driver_phone,
         driver_name  = coalesce(v_offer.driver_name, driver_name),
         fare = v_offer.offered_price,
         accepted_at = now()
   where id = p_ride_id and driver_phone is null
   returning to_jsonb(rides.*) into v_updated;

  if v_updated is null then
    raise exception 'ride_already_taken';
  end if;

  update public.ride_price_offers set status = 'accepted' where id = p_offer_id;
  update public.ride_price_offers set status = 'rejected'
   where ride_id = p_ride_id and id <> p_offer_id and status = 'pending';

  return to_jsonb(v_updated);
end;
$$;
grant execute on function public.accept_ride_price_offer(uuid, uuid, text) to anon, authenticated;
