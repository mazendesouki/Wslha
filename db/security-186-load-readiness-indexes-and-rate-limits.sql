-- security-186: load-readiness pass
-- آمن لإعادة التشغيل (idempotent) — safe to re-run.
--
-- Three independent fixes found during a load-readiness audit:
-- 1. Two hot-path queries with no supporting index (driver matching,
--    scheduled-ride activation) that currently full-table-scan and will
--    get linearly slower as the fleet/ride volume grows.
-- 2. No rate limiting anywhere on customer-facing writes (ride/order
--    creation, chat messages) — a script could flood these with nothing
--    in the database to stop it.
-- 3. Incidental finding while checking table grants: every table in
--    the public schema still carries a TRUNCATE grant to anon/authenticated
--    left over from an early `GRANT ALL` that was never narrowed down when
--    RLS was locked down. PostgREST has no TRUNCATE verb so this isn't
--    reachable through the normal client API, but it's needless privilege
--    with a real blast radius if any other path ever reaches it — revoking
--    it costs nothing and the app never truncates these tables itself.
--
-- Verified live on vtikgyiopkjnrwlqnmfx with tagged synthetic data
-- (inserted and deleted within this migration's own testing, never left
-- in the table): the driver-matching query went from a full Seq Scan
-- (hundreds of buffer reads, growing linearly with driver_locations size)
-- to an Index Scan on the new partial GiST index (8 buffer reads,
-- constant regardless of table size) at 20,000 simulated online drivers.
-- The scheduled-ride query went from a 586-buffer Seq Scan to a 1-buffer
-- Index Scan at 20,000 simulated scheduled rides.

-- === 1. Indexes ===================================================

-- Exactly matches dispatch_find_and_offer()'s WHERE clause, so the
-- planner can do an index-order KNN scan instead of a full table scan
-- + in-memory sort on every single dispatch attempt (every 10s sweep,
-- every new ride/order, every rejected offer).
create index if not exists idx_driver_locations_available_point
  on public.driver_locations using gist (point(lng, lat))
  where is_online = true and ride_id is null and current_order_id is null;

-- activate_scheduled_rides() runs this filter every minute via pg_cron.
create index if not exists idx_rides_scheduled_pending
  on public.rides (scheduled_at)
  where status = 'scheduled';

-- Supports the client-side "you already have an active ride" duplicate
-- booking guard and any admin lookup filtering by customer/driver + status.
create index if not exists idx_rides_customer_status on public.rides (customer_phone, status);
create index if not exists idx_rides_driver_status on public.rides (driver_phone, status);
create index if not exists idx_orders_customer_status on public.orders (customer_phone, status);

-- === 2. Rate limiting ==============================================

create table if not exists public.rate_limit_counters (
  bucket_key text primary key,
  window_started_at timestamptz not null default now(),
  hit_count int not null default 1
);
revoke all on public.rate_limit_counters from anon, authenticated;

-- Fixed-window counter: returns true if this hit is still within the
-- allowed count for the current window, false if the caller should be
-- rejected. Self-resets once the window has elapsed, so a blocked
-- caller is only ever blocked for the remainder of one window.
create or replace function public._rate_limit_hit(p_bucket text, p_max_per_window int, p_window_seconds int)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_row record;
begin
  insert into public.rate_limit_counters (bucket_key, window_started_at, hit_count)
  values (p_bucket, now(), 1)
  on conflict (bucket_key) do update
    set hit_count = case
          when public.rate_limit_counters.window_started_at <= now() - (p_window_seconds || ' seconds')::interval
            then 1
          else public.rate_limit_counters.hit_count + 1
        end,
        window_started_at = case
          when public.rate_limit_counters.window_started_at <= now() - (p_window_seconds || ' seconds')::interval
            then now()
          else public.rate_limit_counters.window_started_at
        end
  returning * into v_row;

  return v_row.hit_count <= p_max_per_window;
end;
$$;
revoke all on function public._rate_limit_hit(text, int, int) from anon, authenticated;

-- Generous thresholds — sized well above any real user's normal pace
-- (including the legitimate "proceed anyway" retry after the duplicate-
-- active-ride dialog) so only a scripted flood ever trips these.
create or replace function public._trg_rate_limit_ride_create()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public._rate_limit_hit('ride_create:' || coalesce(new.customer_phone, ''), 10, 60) then
    raise exception 'too many ride requests, please wait a moment' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_rate_limit_ride_create on public.rides;
create trigger trg_rate_limit_ride_create
  before insert on public.rides
  for each row execute function public._trg_rate_limit_ride_create();

create or replace function public._trg_rate_limit_order_create()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public._rate_limit_hit('order_create:' || coalesce(new.customer_phone, ''), 10, 60) then
    raise exception 'too many order requests, please wait a moment' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_rate_limit_order_create on public.orders;
create trigger trg_rate_limit_order_create
  before insert on public.orders
  for each row execute function public._trg_rate_limit_order_create();

-- === 3. send_ride_message(): add the same floodgate inline =========
-- (it's already a SECURITY DEFINER RPC, not a direct table insert, so
-- the check goes in the function body rather than a trigger. Body is
-- otherwise the live definition verbatim — phone-variant matching and
-- push notification unchanged — with one added rate-limit check.)
create or replace function public.send_ride_message(p_ride_id uuid, p_sender_phone text, p_sender_role text, p_body text)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_id uuid;
  v_ride record;
  v_body text := trim(p_body);
  v_recipient_phone text;
  v_sender_variants text[];
begin
  if v_body is null or length(v_body) = 0 then
    return null;
  end if;

  if not public._rate_limit_hit('ride_msg:' || coalesce(p_sender_phone, ''), 30, 60) then
    raise exception 'too many messages, please slow down' using errcode = 'P0001';
  end if;

  v_sender_variants := array[
    p_sender_phone,
    case when p_sender_phone like '+20%' then '0'||substr(p_sender_phone,4) else p_sender_phone end,
    case when p_sender_phone like '0%'   then '+2'||p_sender_phone           else p_sender_phone end
  ];

  select * into v_ride from public.rides
   where id = p_ride_id
     and (customer_phone = any(v_sender_variants) or driver_phone = any(v_sender_variants));
  if v_ride.id is null then
    raise exception 'NOT_PARTICIPANT';
  end if;

  insert into public.ride_messages(ride_id, sender_phone, sender_role, body)
  values (p_ride_id, p_sender_phone, p_sender_role, v_body)
  returning id into v_id;

  v_recipient_phone := case
    when v_ride.customer_phone = any(v_sender_variants) then v_ride.driver_phone
    else v_ride.customer_phone
  end;

  if v_recipient_phone is not null then
    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-push-secret', public._push_trigger_secret(),
        'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
      ),
      body    := jsonb_build_object(
        'phone', v_recipient_phone,
        'title', '💬 رسالة جديدة',
        'body',  v_body,
        'url',   '/rides',
        'tag',   'wslha-ride-chat-' || p_ride_id
      )
    );
  end if;

  return v_id;
end;
$function$;

-- === 4. Revoke the stray TRUNCATE grants ===========================

do $$
declare r record;
begin
  for r in
    select table_name from information_schema.role_table_grants
    where table_schema = 'public' and grantee in ('anon','authenticated') and privilege_type = 'TRUNCATE'
    group by table_name
  loop
    execute format('revoke truncate on table public.%I from anon, authenticated', r.table_name);
  end loop;
end $$;
