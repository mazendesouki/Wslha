-- ═══════════════════════════════════════════════════════════════
-- Waiting-time penalties, now admin-configurable on both sides:
--
-- 1. Driver-late-to-pickup fee (already existed in mark_ride_arrived(),
--    security-29) — was hardcoded at >5 min grace / 20 ج.م flat fee.
--    Now reads driver_late_grace_minutes / driver_late_fee from
--    app_settings (defaults 5 / 10, matching the requested new default).
--
-- 2. NEW: customer-late-to-board fee — once the driver has marked
--    "arrived", if the customer takes longer than
--    customer_late_grace_minutes (default 5) to actually get in (the
--    arrived → in_progress transition), the customer is charged
--    customer_late_fee_per_minute (default 5) ج.م for every extra
--    minute, deducted from their wallet at the moment the driver taps
--    "ابدأ الرحلة" (same driver_update_ride_status() RPC the app
--    already calls for that transition — see security-48).
-- ═══════════════════════════════════════════════════════════════

insert into public.app_settings (key, value) values
  ('driver_late_grace_minutes',      '5'),
  ('driver_late_fee',                '10'),
  ('customer_late_grace_minutes',    '5'),
  ('customer_late_fee_per_minute',   '5')
on conflict (key) do nothing;

create or replace function public.mark_ride_arrived(p_ride_id text, p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ride        record;
  v_late_minutes int;
  v_fee_applied  boolean := false;
  v_grace        int;
  v_fee          numeric;
begin
  select * into v_ride from public.rides where id::text = p_ride_id for update;
  if not found then
    raise exception 'ride_not_found';
  end if;
  if v_ride.driver_phone is distinct from p_driver_phone then
    raise exception 'not_your_ride';
  end if;
  if v_ride.arrived_at is not null then
    -- already marked — idempotent no-op, no double charge
    return jsonb_build_object('late_minutes', 0, 'fee_applied', false);
  end if;

  v_grace := public._pricing_setting_num('driver_late_grace_minutes', 5, 0)::int;
  v_fee   := public._pricing_setting_num('driver_late_fee', 10, 0);

  v_late_minutes := case
    when v_ride.accepted_at is null then 0
    else greatest(0, floor(extract(epoch from (now() - v_ride.accepted_at)) / 60))::int
  end;

  update public.rides set status = 'arrived', arrived_at = now() where id::text = p_ride_id;

  if v_late_minutes > v_grace then
    v_fee_applied := true;
    perform public.add_wallet_balance(p_driver_phone, -v_fee);
    insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
    values (
      'wtx-late-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
      p_driver_phone, -v_fee, 'penalty', p_ride_id,
      'خصم تأخير وصول (' || v_late_minutes || ' دقيقة)', now()
    );
  end if;

  return jsonb_build_object('late_minutes', v_late_minutes, 'fee_applied', v_fee_applied);
end;
$$;

create or replace function public.driver_update_ride_status(p_ride_id uuid, p_driver_phone text, p_status text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ride public.rides%rowtype;
  v_rows int;
  v_grace numeric;
  v_fee_per_min numeric;
  v_wait_minutes int;
  v_fee numeric;
begin
  if p_status not in ('in_progress', 'completed') then
    raise exception 'invalid_status';
  end if;

  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride_not_found'; end if;
  if v_ride.driver_phone is distinct from p_driver_phone then raise exception 'not_your_ride'; end if;

  if p_status = 'in_progress' then
    update public.rides set status = 'in_progress' where id = p_ride_id;

    -- Customer late-to-board fee — only fires once (guarded by status
    -- actually being 'arrived' beforehand, so a retried/duplicate call
    -- after the row is already 'in_progress' can't double-charge).
    if v_ride.status = 'arrived' and v_ride.arrived_at is not null and v_ride.customer_phone is not null then
      v_grace       := public._pricing_setting_num('customer_late_grace_minutes', 5, 0);
      v_fee_per_min := public._pricing_setting_num('customer_late_fee_per_minute', 5, 0);
      v_wait_minutes := greatest(0, floor(extract(epoch from (now() - v_ride.arrived_at)) / 60))::int;

      if v_wait_minutes > v_grace then
        v_fee := (v_wait_minutes - v_grace) * v_fee_per_min;
        perform public.add_wallet_balance(v_ride.customer_phone, -v_fee);
        insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
        values (
          'wtx-wait-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
          v_ride.customer_phone, -v_fee, 'penalty', p_ride_id::text,
          'خصم انتظار السائق (' || v_wait_minutes || ' دقيقة)', now()
        );
      end if;
    end if;
  else
    update public.rides set status = 'completed', completed_at = now() where id = p_ride_id;
  end if;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
