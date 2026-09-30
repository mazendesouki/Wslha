-- =====================================================================
--  وصّلها — Security #104: تنبيه تلقائي للأدمن عند ارتفاع معدل الإلغاء/الرفض
--
--  مشكلة زي اللي حصلت مع سويتش "متصل/غير متصل" ممكن تتسبب في ارتفاع مفاجئ
--  في نسبة الرحلات/الطلبات الملغاة أو المرفوضة، والأدمن معندوش أي طريقة
--  يعرف بيها غير لو حد اشتكى بالصدفة. الحل: pg_cron كل 10 دقايق بيحسب
--  نسبة الإلغاء/الرفض على الرحلات + الطلبات اللي "اتحسمت" (وصلت لحالة
--  نهائية) خلال نافذة زمنية متحركة، ولو عدّت الحد الأدنى (ومعاها عينة
--  كافية عشان تبقى ذات دلالة إحصائية) بيسجّل تنبيه ويبعت push للأدمن
--  (نفس send-push الموجودة، target='admin' بتدوّر على push_subscriptions/
--  device_tokens لكل حساب role='admin' — الدالة أصلاً بتدعم ده، مفيش أي
--  تعديل مطلوب فيها). فترة تهدئة (cooldown) تمنع تكرار نفس التنبيه كل
--  10 دقايق طول ما المشكلة مستمرة.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value) values
  ('alert_cancellation_enabled', 'true'),
  ('alert_cancellation_rate_threshold', '40'),
  ('alert_cancellation_window_minutes', '30'),
  ('alert_cancellation_min_sample', '5'),
  ('alert_cancellation_cooldown_minutes', '60')
on conflict (key) do nothing;

create table if not exists public.admin_alerts (
  id uuid primary key default gen_random_uuid(),
  alert_type text not null,
  message text not null,
  metric_value numeric,
  threshold numeric,
  sample_size int,
  created_at timestamptz not null default now()
);
create index if not exists idx_admin_alerts_created on public.admin_alerts(created_at desc);

alter table public.admin_alerts enable row level security;
-- مفيش policies لـ anon/authenticated عمدًا — القراءة بس عن طريق
-- admin_list_alerts (security definer، نفس نمط كلمة مرور الأدمن المعتاد).
-- الكتابة بس من check_cancellation_rate_alert (security definer برضه).

create or replace function public.check_cancellation_rate_alert()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_enabled    boolean;
  v_threshold  numeric;
  v_window     int;
  v_min_sample int;
  v_cooldown   int;
  v_last_alert timestamptz;
  v_r_total    int;
  v_r_cancel   int;
  v_o_total    int;
  v_o_cancel   int;
  v_total      int;
  v_cancelled  int;
  v_rate       numeric;
begin
  v_enabled := coalesce((select value from public.app_settings where key = 'alert_cancellation_enabled'), 'true') = 'true';
  if not v_enabled then return; end if;

  v_threshold  := coalesce((select value::numeric from public.app_settings where key = 'alert_cancellation_rate_threshold'), 40);
  v_window     := coalesce((select value::int     from public.app_settings where key = 'alert_cancellation_window_minutes'), 30);
  v_min_sample := coalesce((select value::int     from public.app_settings where key = 'alert_cancellation_min_sample'), 5);
  v_cooldown   := coalesce((select value::int     from public.app_settings where key = 'alert_cancellation_cooldown_minutes'), 60);

  select max(created_at) into v_last_alert from public.admin_alerts where alert_type = 'cancellation_rate';
  if v_last_alert is not null and v_last_alert > now() - (v_cooldown || ' minutes')::interval then
    return; -- لسه في فترة التهدئة
  end if;

  -- المقام: بس الرحلات/الطلبات اللي "اتحسمت" (وصلت لحالة نهائية) في
  -- النافذة الزمنية — رحلة لسه pending ومالهاش سائق مش معناها إلغاء.
  select
    count(*) filter (where status in ('completed', 'cancelled')),
    count(*) filter (where status = 'cancelled')
  into v_r_total, v_r_cancel
  from public.rides
  where created_at >= now() - (v_window || ' minutes')::interval;

  select
    count(*) filter (where status in ('delivered', 'rejected', 'cancelled')),
    count(*) filter (where status in ('rejected', 'cancelled'))
  into v_o_total, v_o_cancel
  from public.orders
  where created_at >= now() - (v_window || ' minutes')::interval;

  v_total     := coalesce(v_r_total, 0) + coalesce(v_o_total, 0);
  v_cancelled := coalesce(v_r_cancel, 0) + coalesce(v_o_cancel, 0);

  if v_total < v_min_sample then return; end if;

  v_rate := round(100.0 * v_cancelled / v_total, 1);
  if v_rate < v_threshold then return; end if;

  insert into public.admin_alerts (alert_type, message, metric_value, threshold, sample_size)
  values (
    'cancellation_rate',
    'معدل الإلغاء/الرفض وصل ' || v_rate || '% خلال آخر ' || v_window || ' دقيقة (' || v_cancelled || ' من ' || v_total || ')',
    v_rate, v_threshold, v_total
  );

  perform net.http_post(
    url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-push-secret', public._push_trigger_secret(),
      'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
    ),
    body    := jsonb_build_object(
      'target', 'admin',
      'title',  '⚠️ ارتفاع معدل الإلغاء',
      'body',   'معدل الإلغاء/الرفض ' || v_rate || '% خلال آخر ' || v_window || ' دقيقة — راجع لوحة التحكم',
      'url',    '/admin'
    )
  );
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'check-cancellation-rate-alert';
select cron.schedule('check-cancellation-rate-alert', '*/10 * * * *', $$select public.check_cancellation_rate_alert();$$);

create or replace function public.admin_list_alerts(p_admin_phone text, p_admin_password text, p_limit int default 20)
returns setof admin_alerts
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return;
  end if;
  return query select * from public.admin_alerts order by created_at desc limit p_limit;
end;
$$;
grant execute on function public.admin_list_alerts(text, text, int) to anon, authenticated;
