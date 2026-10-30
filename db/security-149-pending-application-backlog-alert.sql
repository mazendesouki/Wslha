-- =====================================================================
--  وصّلها — Security #149: تنبيه تراكم طلبات السائقين/التجار اللي لسه
--  محتاجة مراجعة الأدمن
--
--  خامس أتمتة (Workflow Automation)، نفس نمط security-104/145/146/148.
--  لحد دلوقتي مفيش أي طريقة للأدمن يعرف إن فيه طلب سائق أو تاجر فضل
--  "pending" من غير مراجعة لفترة طويلة — غير إنه يفتح اللوحة ويتصفح
--  بنفسه. التأخير ده بالذات مكلف أكتر من غيره: سائق/تاجر مستني موافقة
--  لمدة طويلة غالبًا ينسحب وما يكمّلش تسجيله خالص (churn في أول خطوة).
--
--  يشتغل كل 6 ساعات، وبيفحص driver_applications و merchant_applications
--  (نفس العمودين status/created_at في الاتنين) — لو طلب فضل pending
--  أطول من الحد المسموح، بيسجّل admin_alert (نفس جدول/نمط
--  security-104/145/148) بكولداون لكل طلب على حدة (24 ساعة) عشان
--  يفضل يتنبّه لحد ما حد يراجعه، من غير سبام كل 6 ساعات.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value) values
  ('alert_pending_application_enabled', 'true'),
  ('alert_pending_application_hours', '24'),
  ('alert_pending_application_cooldown_hours', '24')
on conflict (key) do nothing;

create or replace function public.check_pending_application_backlog()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_enabled   boolean;
  v_hours     int;
  v_cooldown  int;
  v_row       record;
begin
  v_enabled := coalesce((select value from public.app_settings where key = 'alert_pending_application_enabled'), 'true') = 'true';
  if not v_enabled then return; end if;

  v_hours    := coalesce((select value::int from public.app_settings where key = 'alert_pending_application_hours'), 24);
  v_cooldown := coalesce((select value::int from public.app_settings where key = 'alert_pending_application_cooldown_hours'), 24);

  for v_row in
    select id::text as id, phone, full_name as name, created_at, 'driver' as kind
      from public.driver_applications
     where status = 'pending' and created_at <= now() - (v_hours || ' hours')::interval
    union all
    select id::text as id, phone, business_name as name, created_at, 'merchant' as kind
      from public.merchant_applications
     where status = 'pending' and created_at <= now() - (v_hours || ' hours')::interval
  loop
    if exists (
      select 1 from public.admin_alerts
       where reference_type = 'pending_application_' || v_row.kind and reference_id = v_row.id
         and created_at > now() - (v_cooldown || ' hours')::interval
    ) then
      continue;
    end if;

    insert into public.admin_alerts (alert_type, message, metric_value, threshold, reference_type, reference_id)
    values (
      'pending_application_backlog',
      (case when v_row.kind = 'driver' then 'طلب سائق' else 'طلب تاجر' end)
        || ' (' || coalesce(v_row.name, v_row.phone) || ') لسه محتاج مراجعة من '
        || extract(epoch from (now() - v_row.created_at))::int / 3600 || ' ساعة',
      extract(epoch from (now() - v_row.created_at))::int / 3600, v_hours,
      'pending_application_' || v_row.kind, v_row.id
    );

    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type','application/json','x-push-secret', public._push_trigger_secret(),
                                     'apikey','sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'),
      body    := jsonb_build_object('target','admin',
                                     'title', case when v_row.kind = 'driver' then '⏳ طلب سائق محتاج مراجعة' else '⏳ طلب تاجر محتاج مراجعة' end,
                                     'body', coalesce(v_row.name, v_row.phone) || ' مستنّي مراجعة', 'url','/admin')
    );
  end loop;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'check-pending-application-backlog';
select cron.schedule('check-pending-application-backlog', '0 */6 * * *', $$select public.check_pending_application_backlog();$$);
