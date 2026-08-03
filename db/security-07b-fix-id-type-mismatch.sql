-- Fixes "operator does not exist: uuid = text" thrown by
-- settle_ride_commission / settle_order_commission on ride/order
-- completion — same root cause as security-09b: rides.id and orders.id
-- are declared uuid in production even though the original migration
-- assumed text, so p_ride_id/p_order_id (text parameters) need an
-- explicit ::text cast on the id column to compare safely either way.

create or replace function public.settle_ride_commission(
  p_ride_id      text,
  p_driver_phone text
)
returns table(commission numeric, driver_earn numeric, rate numeric)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ride       public.rides%rowtype;
  v_rate_key   text;
  v_rate_raw   text;
  v_rate       numeric;
  v_commission numeric;
  v_earn       numeric;
  v_note_pct   text;
begin
  if p_driver_phone is null or length(trim(p_driver_phone)) = 0 then
    raise exception 'driver_phone_required';
  end if;

  select * into v_ride from public.rides where id::text = p_ride_id for update;
  if not found then
    raise exception 'ride_not_found';
  end if;

  if v_ride.driver_phone is distinct from p_driver_phone then
    raise exception 'not_your_ride';
  end if;

  if v_ride.status <> 'completed' then
    raise exception 'ride_not_completed';
  end if;

  if v_ride.commission_settled then
    select abs(amount) into v_commission
      from public.wallet_transactions
      where reference_id = p_ride_id and type = 'commission'
      order by created_at desc limit 1;
    select amount into v_earn
      from public.wallet_transactions
      where reference_id = p_ride_id and type = 'earning'
      order by created_at desc limit 1;
    return query select coalesce(v_commission, 0), coalesce(v_earn, 0), 0::numeric;
    return;
  end if;

  v_rate_key := case
    when v_ride.ride_type = 'airport'  then 'commission_airport'
    when v_ride.ride_type = 'external' then 'commission_external'
    else 'commission_ride'
  end;

  select value into v_rate_raw from public.app_settings where key = v_rate_key;
  v_rate := nullif(v_rate_raw, '')::numeric;
  if v_rate is null or v_rate < 0 or v_rate >= 100 then
    v_rate := 15;
  end if;

  v_commission := round(coalesce(v_ride.fare, 0) * v_rate / 100);
  v_earn       := coalesce(v_ride.fare, 0) - v_commission;
  v_note_pct   := round(v_rate)::text;

  perform public.add_wallet_balance(p_driver_phone, v_earn);

  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'wtx-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    p_driver_phone, v_earn, 'earning', p_ride_id,
    'أرباح رحلة — بعد خصم العمولة ' || v_note_pct || '%', now()
  );

  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'pcom-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    'platform', v_commission, 'commission', p_ride_id,
    'عمولة رحلة — ' || v_note_pct || '% من ' || coalesce(v_ride.fare, 0)::text || ' ج.م', now()
  );

  update public.rides set commission_settled = true where id::text = p_ride_id;

  return query select v_commission, v_earn, v_rate;
end;
$$;

create or replace function public.settle_order_commission(
  p_order_id     text,
  p_driver_phone text
)
returns table(commission numeric, driver_earn numeric, rate numeric)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_order      public.orders%rowtype;
  v_rate_raw   text;
  v_rate       numeric;
  v_commission numeric;
  v_earn       numeric;
  v_note_pct   text;
begin
  if p_driver_phone is null or length(trim(p_driver_phone)) = 0 then
    raise exception 'driver_phone_required';
  end if;

  select * into v_order from public.orders where id::text = p_order_id for update;
  if not found then
    raise exception 'order_not_found';
  end if;

  if v_order.driver_phone is distinct from p_driver_phone then
    raise exception 'not_your_order';
  end if;

  if v_order.status <> 'delivered' then
    raise exception 'order_not_delivered';
  end if;

  if v_order.commission_settled then
    select abs(amount) into v_commission
      from public.wallet_transactions
      where reference_id = p_order_id and type = 'commission'
      order by created_at desc limit 1;
    select amount into v_earn
      from public.wallet_transactions
      where reference_id = p_order_id and type = 'earning'
      order by created_at desc limit 1;
    return query select coalesce(v_commission, 0), coalesce(v_earn, 0), 0::numeric;
    return;
  end if;

  select value into v_rate_raw from public.app_settings where key = 'commission_delivery';
  v_rate := nullif(v_rate_raw, '')::numeric;
  if v_rate is null or v_rate < 0 or v_rate >= 100 then
    v_rate := 15;
  end if;

  v_commission := round(coalesce(v_order.delivery_fee, 0) * v_rate / 100);
  v_earn       := coalesce(v_order.delivery_fee, 0) - v_commission;
  v_note_pct   := round(v_rate)::text;

  perform public.add_wallet_balance(p_driver_phone, v_earn);

  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'wtx-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    p_driver_phone, v_earn, 'earning', p_order_id,
    'أرباح توصيل — بعد خصم العمولة ' || v_note_pct || '%', now()
  );

  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'pcom-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    'platform', v_commission, 'commission', p_order_id,
    'عمولة توصيل — ' || v_note_pct || '% من ' || coalesce(v_order.delivery_fee, 0)::text || ' ج.م', now()
  );

  update public.orders set commission_settled = true where id::text = p_order_id;

  return query select v_commission, v_earn, v_rate;
end;
$$;

grant execute on function public.settle_ride_commission(text, text)  to anon, authenticated;
grant execute on function public.settle_order_commission(text, text) to anon, authenticated;
