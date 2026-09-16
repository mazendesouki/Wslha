-- ═══════════════════════════════════════════════════════════════
-- Adds an on/off switch for the driver-late-to-pickup fee (was always-on
-- since it first existed in security-29, only the grace/fee amount was
-- configurable via security-63) — turned OFF here per explicit request,
-- with the admin able to re-enable it later from the dashboard. The
-- customer-late-to-board fee (driver_update_ride_status()) is untouched
-- — this only disables the fee charged TO the driver.
-- ═══════════════════════════════════════════════════════════════

insert into public.app_settings (key, value) values
  ('driver_late_fee_enabled', 'false')
on conflict (key) do nothing;

-- In case the row already existed from a prior run of this same file
-- (on conflict do nothing above would then skip it) — make sure it's
-- explicitly off right now, since that's the point of this migration.
update public.app_settings set value = 'false', updated_at = now()
where key = 'driver_late_fee_enabled';

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
  v_enabled      boolean;
begin
  select * into v_ride from public.rides where id::text = p_ride_id for update;
  if not found then
    raise exception 'ride_not_found';
  end if;
  if v_ride.driver_phone is distinct from p_driver_phone then
    raise exception 'not_your_ride';
  end if;
  if v_ride.arrived_at is not null then
    return jsonb_build_object('late_minutes', 0, 'fee_applied', false);
  end if;

  select coalesce(value, 'false') = 'true' into v_enabled
  from public.app_settings where key = 'driver_late_fee_enabled';

  v_grace := public._pricing_setting_num('driver_late_grace_minutes', 5, 0)::int;
  v_fee   := public._pricing_setting_num('driver_late_fee', 10, 0);

  v_late_minutes := case
    when v_ride.accepted_at is null then 0
    else greatest(0, floor(extract(epoch from (now() - v_ride.accepted_at)) / 60))::int
  end;

  update public.rides set status = 'arrived', arrived_at = now() where id::text = p_ride_id;

  if coalesce(v_enabled, false) and v_late_minutes > v_grace then
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
