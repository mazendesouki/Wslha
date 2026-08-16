-- =====================================================================
--  وصّلها — Security #20: إصلاح مقارنة uuid/text في confirm_order_delivery
--
--  الدالة كانت بتقارن orders.id (نوعه uuid) مباشرة بـ p_order_id (نوعه
--  text) من غير تحويل، فبيرمي: "operator does not exist: uuid = text".
--  الإصلاح: تحويل صريح p_order_id::uuid قبل المقارنة. باقي الدالة زي
--  ما هي بالظبط.
--
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.confirm_order_delivery(p_order_id text, p_otp text, p_driver_phone text)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_rows int;
begin
  update public.orders
    set status = 'delivered', delivered_at = now()
  where id = p_order_id::uuid
    and driver_phone = p_driver_phone
    and delivery_otp = p_otp
    and status <> 'delivered';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$function$;
