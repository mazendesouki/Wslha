-- =====================================================================
--  وصّلها — Security #40: إلغاء الرحلة من العميل بعد قبول السائق
--
--  قبل كده cancelRide() في التطبيق كانت بتعمل UPDATE مباشر على rides
--  (status='cancelled') من غير أي تحقق من الملكية أصلاً — أي حد يعرف
--  رقم الرحلة (rideId) كان يقدر يلغيها. والشاشة كانت بتسمح بالإلغاء وقت
--  status='pending' بس، يعني بعد ما السائق يقبل الرحلة العميل مكنش
--  عنده خيار يلغي خالص.
--
--  الدالة دي:
--   • بتتحقق إن رقم تليفون العميل اللي بعته فعلاً هو صاحب الرحلة
--     (بنفس نمط مطابقة الصيغتين +20/0 المستخدم في accept_ride_price_offer).
--   • بتسمح بالإلغاء طول ما الرحلة لسه pending / accepted / arrived —
--     يعني قبل ما السائق يبدأ الرحلة فعليًا (in_progress)، وطبعًا مش
--     بعد ما تخلص أو تتلغي قبل كده.
--   • مفيش دالة أو زرار مقابل للسائق يلغي بيها رحلة قبلها — الإلغاء من
--     جهة السائق مش موجود في التطبيق أصلاً (زي ما driver-dashboard.astro
--     بيقفل زرار الرفض فور القبول)، فالحق ده فعليًا للعميل بس.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.customer_cancel_ride(
  p_ride_id uuid, p_customer_phone text
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

  if v_ride.status not in ('pending', 'accepted', 'arrived') then
    raise exception 'cannot_cancel_now';
  end if;

  update public.rides set status = 'cancelled' where id = p_ride_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.customer_cancel_ride(uuid, text) to anon, authenticated;
