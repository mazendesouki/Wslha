-- security-193: fix N+1 in send_maintenance_due_reminders
-- آمن لإعادة التشغيل (idempotent) — safe to re-run.
--
-- Was: a PL/pgSQL loop over every approved driver, calling
-- get_maintenance_due_status(phone) once per driver (a query against
-- vehicle_service_logs + maintenance_catalog_items each time), then a
-- per-row `exists(select ... from notifications)` dedup check inside a
-- second nested loop. Cheap at today's driver count, but both the
-- per-driver function calls and the per-row dedup check scale linearly
-- with (drivers × due items) rather than running as a single query.
--
-- Now: one set-based query (CROSS JOIN LATERAL still calls
-- get_maintenance_due_status once per driver — that part is inherent to
-- what the function computes — but the dedup check is now a single
-- anti-join against notifications instead of one EXISTS per row), then a
-- single tight loop only over the rows that actually need a push sent
-- (push notifications are inherently one HTTP call per recipient, so
-- that part can't be batched away).

create or replace function public.send_maintenance_due_reminders()
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_row record;
  v_tag text;
begin
  for v_row in
    select
      da.phone::text as phone,
      s.item_key, s.label_ar, s.status, s.km_since,
      'wslha-maint-due-' || da.phone::text || '-' || s.item_key || '-' || s.status
        || '-' || coalesce(s.last_done_odometer::text, 'none') as tag
    from public.driver_applications da
    cross join lateral public.get_maintenance_due_status(da.phone::text) s
    where da.status = 'approved'
      and s.status in ('due_soon', 'overdue')
      and not exists (
        select 1 from public.notifications n
        where n.phone = da.phone::text
          and n.tag = 'wslha-maint-due-' || da.phone::text || '-' || s.item_key || '-' || s.status
            || '-' || coalesce(s.last_done_odometer::text, 'none')
      )
  loop
    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-push-secret', public._push_trigger_secret(),
        'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
      ),
      body    := jsonb_build_object(
        'phone', v_row.phone,
        'title', case when v_row.status = 'overdue' then '⛔ صيانة متأخرة' else '⏰ صيانة قربت تستحق' end,
        'body',  case
                    when v_row.status = 'overdue'
                      then v_row.label_ar || ' متأخرة — ' || coalesce(v_row.km_since::text, '0') || ' كم فوق الموعد'
                    else v_row.label_ar || ' قربت تستحق — سجّلها لما تخلّصها'
                  end,
        'url',   '/driver-dashboard',
        'tag',   v_row.tag
      )
    );
  end loop;
end;
$function$;
