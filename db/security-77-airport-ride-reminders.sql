-- =====================================================================
--  وصّلها — Security #77: رحلات المطار المجدولة — منع خصم تأخير خاطئ
--  + تذكير "رحلة غدا" للسائق والعميل
--
--  رحلات المطار أصلاً بتتحجز بميعاد طيران مستقبلي (flight_time —
--  security-32) وبتظهر للسواقين فورًا يقبلوها زي أي رحلة (accept_airport_ride
--  — security-65)، فمفيش داعي نأخّر ظهورها زي الرحلات العادية المجدولة
--  (security-76). لكن ده كشف باگين حقيقيين:
--
--   1) mark_ride_arrived (security-29/63/64) كان بيحسب "تأخير الوصول"
--      من وقت القبول (accepted_at) — لو سائق قبل رحلة مطار يوم كامل
--      قبل الطيران، كان هيتحصّل عليه "خصم تأخير" كبير غلط لمجرد إنه
--      وصل بعد ساعات من وقت القبول، مع إن ده طبيعي جدًا لرحلة مجدولة.
--      الحل: رحلة مطار ليها flight_time بتتعفى بالكامل من حساب التأخير
--      ده (مفيش معنى لـ"تأخير" بالنسبة لرحلة اتقبلت قبل ميعادها بوقت).
--
--   2) مفيش أي تذكير للطرفين قبل رحلة المطار — العميل والسائق ممكن
--      ينسوا رحلة قبلوها/حجزوها من يوم أو أكتر. الحل: Job جديد بـ
--      pg_cron بيدوّر كل نص ساعة على رحلات مطار (لسه مكتملة، وميعاد
--      طيرانها خلال الـ24 ساعة الجاية) ومتبعتلهاش تذكير قبل كده،
--      ويبعت push للعميل ولو فيه سائق متعيّن للسائق كمان.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.rides add column if not exists reminder_sent_at timestamptz;

-- ---------------------------------------------------------------------
-- 1) mark_ride_arrived — إعفاء رحلات المطار المجدولة من خصم التأخير.
-- ---------------------------------------------------------------------
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

  update public.rides set status = 'arrived', arrived_at = now() where id::text = p_ride_id;

  -- رحلة مطار بميعاد طيران معروف: "تأخير من وقت القبول" مفهوم غلط هنا
  -- (السائق ممكن يكون قابلها من يوم كامل قبل الطيران) — تعفى تمامًا.
  if v_ride.ride_type = 'airport' and v_ride.flight_time is not null then
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
grant execute on function public.mark_ride_arrived(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) تذكير "رحلة غدا" — يوم قبل ميعاد الطيران، للعميل وللسائق (لو معيّن).
-- ---------------------------------------------------------------------
insert into public.app_settings (key, value) values
  ('feature_airport_reminders_enabled', 'true')
on conflict (key) do nothing;

create or replace function public.send_airport_ride_reminders()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_enabled boolean;
  v_ride record;
begin
  select coalesce(value, 'false') = 'true' into v_enabled
  from public.app_settings where key = 'feature_airport_reminders_enabled';
  if not coalesce(v_enabled, true) then return; end if;

  for v_ride in
    select * from public.rides
     where ride_type = 'airport'
       and flight_time is not null
       and reminder_sent_at is null
       and status in ('pending', 'accepted', 'arrived', 'in_progress')
       and flight_time > now()
       and flight_time <= now() + interval '24 hours'
  loop
    update public.rides set reminder_sent_at = now() where id = v_ride.id;

    if v_ride.customer_phone is not null then
      perform net.http_post(
        url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'x-push-secret', public._push_trigger_secret(),
          'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
        ),
        body    := jsonb_build_object(
          'phone', v_ride.customer_phone,
          'title', '🛫 عندك رحلة مطار بكرة',
          'body',  coalesce(v_ride.from_area, '') || ' ← ' || coalesce(v_ride.to_area, ''),
          'url',   '/rides',
          'tag',   'wslha-airport-reminder-' || v_ride.id
        )
      );
    end if;

    if v_ride.driver_phone is not null then
      perform net.http_post(
        url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'x-push-secret', public._push_trigger_secret(),
          'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
        ),
        body    := jsonb_build_object(
          'phone', v_ride.driver_phone,
          'title', '🛫 عندك رحلة مطار بكرة',
          'body',  coalesce(v_ride.from_area, '') || ' ← ' || coalesce(v_ride.to_area, ''),
          'url',   '/driver-dashboard',
          'tag',   'wslha-airport-reminder-' || v_ride.id
        )
      );
    end if;
  end loop;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'airport-ride-reminders';
select cron.schedule('airport-ride-reminders', '*/30 * * * *', $$select public.send_airport_ride_reminders();$$);
