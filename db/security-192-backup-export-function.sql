-- security-192: full-database JSON export for the DIY backup
-- آمن لإعادة التشغيل (idempotent) — safe to re-run.
--
-- Not exposed to anon/authenticated — only ever called with elevated
-- (service-role-level) access, same as every admin/maintenance function
-- in this project. Builds one JSON document covering every public table
-- except a short, deliberate exclusion list of genuinely transient or
-- regenerate-on-demand data:
--   driver_locations    — live GPS ping, stale within seconds
--   dispatch_offers     — expires in 25 seconds by design
--   otps                — short-lived verification codes
--   login_attempts      — security counters, reset naturally
--   rate_limit_counters — pure throttling state
--   device_tokens       — push tokens, re-registered automatically on next app open
-- notifications is capped to the most recent 2000 rows (of 12,000+) to
-- keep the export a manageable size — it's a push-history log, not
-- financial/business state, so this is a size tradeoff, not a data-
-- integrity one.

create or replace function public._export_backup_json()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_result jsonb := '{}'::jsonb;
  v_table text;
  v_data jsonb;
  v_exclude text[] := array['driver_locations','dispatch_offers','otps','login_attempts','rate_limit_counters','device_tokens'];
begin
  for v_table in
    select table_name from information_schema.tables
    where table_schema = 'public' and table_type = 'BASE TABLE'
      and table_name <> all(v_exclude)
    order by table_name
  loop
    if v_table = 'notifications' then
      execute format('select coalesce(jsonb_agg(t), ''[]''::jsonb) from (select * from public.%I order by created_at desc limit 2000) t', v_table) into v_data;
    else
      execute format('select coalesce(jsonb_agg(t), ''[]''::jsonb) from (select * from public.%I) t', v_table) into v_data;
    end if;
    v_result := v_result || jsonb_build_object(v_table, v_data);
  end loop;

  return jsonb_build_object('exported_at', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'tables', v_result);
end;
$$;

revoke all on function public._export_backup_json() from anon, authenticated;
