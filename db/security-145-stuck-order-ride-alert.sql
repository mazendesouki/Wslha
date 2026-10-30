-- =====================================================================
--  وصّلها — Security #145: تنبيه الأدمن عند تعليق رحلة/طلب بدون سائق
--
--  نفس فكرة security-104 (تنبيه ارتفاع معدل الإلغاء) لكن لمشكلة مختلفة:
--  رحلة فورية (مش مجدولة ومش مطار) فضلت pending من غير أي سائق قبلها،
--  أو طلب لسه pending من غير رد التاجر، أو طلب جاهز (ready_at) من غير
--  سائق اتعيّن ليه — كل دول مؤشر حقيقي إن حاجة واقفة (مفيش سواقين
--  قريبين، التاجر مش شغّال، باگ في التوزيع) قبل ما العميل يشتكي.
--
--  استبعدنا عمدًا:
--  - الرحلات المجدولة (scheduled_at > now()) — لسه معلش توقيتها.
--  - رحلات المطار — بتتحجز قدام ميعاد الطيران بوقت طويل عمدًا
--    (security-77)، فوجودها pending لفترة طويلة طبيعي جدًا.
--
--  كل تنبيه بيتسجّل بـ reference_type/reference_id (عمودين جداد على
--  admin_alerts) عشان الـ cooldown يكون *لكل رحلة/طلب على حدة*، مش
--  cooldown عام زي security-104 — رحلة واحدة واقفة من ساعتين لازم
--  تفضل تنبّه (بعد الكولداون) لحد ما حد يتعامل معها، لكن من غير سبام
--  كل 5 دقايق.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.admin_alerts add column if not exists reference_type text;
alter table public.admin_alerts add column if not exists reference_id text;
create index if not exists idx_admin_alerts_reference on public.admin_alerts(reference_type, reference_id, created_at desc);

insert into public.app_settings (key, value) values
  ('alert_stuck_enabled', 'true'),
  ('alert_stuck_ride_minutes', '10'),
  ('alert_stuck_order_pending_minutes', '10'),
  ('alert_stuck_order_ready_minutes', '15'),
  ('alert_stuck_cooldown_minutes', '30')
on conflict (key) do nothing;

create or replace function public.check_stuck_dispatch_alert()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_enabled        boolean;
  v_ride_minutes   int;
  v_pending_minutes int;
  v_ready_minutes  int;
  v_cooldown       int;
  v_row            record;
begin
  v_enabled := coalesce((select value from public.app_settings where key = 'alert_stuck_enabled'), 'true') = 'true';
  if not v_enabled then return; end if;

  v_ride_minutes    := coalesce((select value::int from public.app_settings where key = 'alert_stuck_ride_minutes'), 10);
  v_pending_minutes := coalesce((select value::int from public.app_settings where key = 'alert_stuck_order_pending_minutes'), 10);
  v_ready_minutes   := coalesce((select value::int from public.app_settings where key = 'alert_stuck_order_ready_minutes'), 15);
  v_cooldown        := coalesce((select value::int from public.app_settings where key = 'alert_stuck_cooldown_minutes'), 30);

  -- 1) رحلة فورية pending من غير سائق لفترة أطول من المسموح.
  for v_row in
    select id, ride_type, from_area, to_area, created_at
      from public.rides
     where status = 'pending'
       and driver_phone is null
       and coalesce(ride_type, 'local') <> 'airport'
       and (scheduled_at is null or scheduled_at <= now())
       and created_at <= now() - (v_ride_minutes || ' minutes')::interval
  loop
    if exists (
      select 1 from public.admin_alerts
       where reference_type = 'ride' and reference_id = v_row.id::text
         and created_at > now() - (v_cooldown || ' minutes')::interval
    ) then
      continue;
    end if;

    insert into public.admin_alerts (alert_type, message, metric_value, threshold, reference_type, reference_id)
    values (
      'stuck_ride',
      'رحلة من ' || coalesce(v_row.from_area, '؟') || ' إلى ' || coalesce(v_row.to_area, '؟')
        || ' لسه من غير سائق بعد ' || extract(epoch from (now() - v_row.created_at))::int / 60 || ' دقيقة',
      extract(epoch from (now() - v_row.created_at))::int / 60, v_ride_minutes, 'ride', v_row.id::text
    );
    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type','application/json','x-push-secret', public._push_trigger_secret(),
                                     'apikey','sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'),
      body    := jsonb_build_object('target','admin','title','⚠️ رحلة بدون سائق',
                                     'body', coalesce(v_row.from_area,'؟') || ' ← ' || coalesce(v_row.to_area,'؟') || ' لسه واقفة', 'url','/admin')
    );
  end loop;

  -- 2) طلب pending من غير رد التاجر لفترة أطول من المسموح.
  for v_row in
    select id, store_id, created_at from public.orders
     where status = 'pending' and accepted_at is null
       and created_at <= now() - (v_pending_minutes || ' minutes')::interval
  loop
    if exists (
      select 1 from public.admin_alerts
       where reference_type = 'order_pending' and reference_id = v_row.id::text
         and created_at > now() - (v_cooldown || ' minutes')::interval
    ) then
      continue;
    end if;

    insert into public.admin_alerts (alert_type, message, metric_value, threshold, reference_type, reference_id)
    values (
      'stuck_order',
      'طلب لسه من غير رد التاجر بعد ' || extract(epoch from (now() - v_row.created_at))::int / 60 || ' دقيقة',
      extract(epoch from (now() - v_row.created_at))::int / 60, v_pending_minutes, 'order_pending', v_row.id::text
    );
    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type','application/json','x-push-secret', public._push_trigger_secret(),
                                     'apikey','sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'),
      body    := jsonb_build_object('target','admin','title','⚠️ طلب بدون رد التاجر','body','طلب لسه معلّق','url','/admin')
    );
  end loop;

  -- 3) طلب جاهز (ready_at) من غير سائق اتعيّن ليه لفترة أطول من المسموح.
  for v_row in
    select id, store_id, ready_at from public.orders
     where status = 'preparing' and ready_at is not null and driver_phone is null
       and ready_at <= now() - (v_ready_minutes || ' minutes')::interval
  loop
    if exists (
      select 1 from public.admin_alerts
       where reference_type = 'order_ready' and reference_id = v_row.id::text
         and created_at > now() - (v_cooldown || ' minutes')::interval
    ) then
      continue;
    end if;

    insert into public.admin_alerts (alert_type, message, metric_value, threshold, reference_type, reference_id)
    values (
      'stuck_order',
      'طلب جاهز من غير سائق بعد ' || extract(epoch from (now() - v_row.ready_at))::int / 60 || ' دقيقة',
      extract(epoch from (now() - v_row.ready_at))::int / 60, v_ready_minutes, 'order_ready', v_row.id::text
    );
    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type','application/json','x-push-secret', public._push_trigger_secret(),
                                     'apikey','sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'),
      body    := jsonb_build_object('target','admin','title','⚠️ طلب جاهز بدون سائق','body','طلب جاهز معلّق','url','/admin')
    );
  end loop;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'check-stuck-dispatch-alert';
select cron.schedule('check-stuck-dispatch-alert', '*/5 * * * *', $$select public.check_stuck_dispatch_alert();$$);
