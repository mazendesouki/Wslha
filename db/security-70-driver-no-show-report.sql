-- =====================================================================
--  وصّلها — Security #70: بلاغ "العميل لم يحضر" (No-show) من السائق
--
--  security-40-customer-cancel-ride.sql وثّق صراحة إن مفيش أي طريقة
--  للسائق يلغي بيها رحلة — لو العميل اتأخر جدًا أو مجاش خالص، السائق
--  كان عالق: مفيش زرار يقفل بيه الرحلة ويتحرر يقبل رحلة تانية، غير
--  خصم-بالدقيقة اللي بيتطبق بس لو الرحلة فعليًا بدأت (customer_late_fee
--  في security-63)، وده مش بديل عن الإلغاء.
--
--  الحل: driver_report_no_show — يسمح للسائق يقفل الرحلة (status →
--  cancelled) لو:
--   • هو فعلاً صاحب الرحلة،
--   • الحالة arrived (وصل لنقطة الانطلاق) ومسجّل arrived_at،
--   • واستنى مدة >= no_show_grace_minutes (افتراضي 10 د) من وقت الوصول
--     — نفس التحقق بيتعاد سيرفر-سايد حتى لو الواجهة سمحت بالضغط بدري.
--
--  عند التنفيذ: العميل بيتخصم منه no_show_fee (افتراضي 15 ج.م) تعويض
--  عدم الحضور، والسائق بياخد نفس المبلغ تعويض وقته وبنزينه — نفس نمط
--  wallet_transactions المستخدم في كل تسويات المحفظة في المشروع.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value) values
  ('no_show_grace_minutes', '10'),
  ('no_show_fee', '15')
on conflict (key) do nothing;

create or replace function public.driver_report_no_show(p_ride_id uuid, p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ride record;
  v_grace int;
  v_fee numeric;
  v_waited_minutes int;
begin
  select * into v_ride from public.rides where id = p_ride_id for update;
  if v_ride.id is null then
    raise exception 'ride_not_found';
  end if;
  if v_ride.driver_phone is distinct from p_driver_phone then
    raise exception 'not_your_ride';
  end if;
  if v_ride.status <> 'arrived' or v_ride.arrived_at is null then
    raise exception 'not_waiting';
  end if;

  v_grace := public._pricing_setting_num('no_show_grace_minutes', 10, 0)::int;
  v_waited_minutes := greatest(0, floor(extract(epoch from (now() - v_ride.arrived_at)) / 60))::int;
  if v_waited_minutes < v_grace then
    raise exception 'grace_not_elapsed';
  end if;

  v_fee := public._pricing_setting_num('no_show_fee', 15, 0);

  update public.rides set status = 'cancelled' where id = p_ride_id;

  perform public.add_wallet_balance(v_ride.customer_phone, -v_fee);
  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'wtx-noshow-cust-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    v_ride.customer_phone, -v_fee, 'no_show_penalty', p_ride_id::text,
    'رسوم عدم حضور بعد ' || v_waited_minutes || ' دقيقة انتظار', now()
  );

  perform public.add_wallet_balance(p_driver_phone, v_fee);
  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'wtx-noshow-drv-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    p_driver_phone, v_fee, 'no_show_compensation', p_ride_id::text,
    'تعويض انتظار — العميل لم يحضر', now()
  );

  return jsonb_build_object('waited_minutes', v_waited_minutes, 'fee', v_fee);
end;
$$;

grant execute on function public.driver_report_no_show(uuid, text) to anon, authenticated;
