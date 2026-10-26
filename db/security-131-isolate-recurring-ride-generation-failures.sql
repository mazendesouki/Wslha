-- =====================================================================
--  وصّلها — Security #131: عزل فشل توليد الرحلات المتكررة عن بعضها
--
--  security-127 أضاف trigger يرفض الإدخال في rides لو rides_local/
--  rides_external/rides_airport مقفولة. لكن generate_recurring_rides()
--  (شغالة كل 15 دقيقة عبر pg_cron) بتلف على كل الجداول اليومية في حلقة
--  واحدة من غير أي عزل للأخطاء — لو رحلة متكررة واحدة نوعها (مثلاً
--  external) مقفول، الـ exception بيلغي المعاملة كلها، يعني محدش من
--  باقي العملاء (local/airport) ياخد رحلته المتكررة النهاردة، والدالة
--  هتفضل تفشل بصمت كل 15 دقيقة لحد ما حد يلاحظ.
--
--  الحل: نفس منطق الدالة، لكن كل إدخال رحلة في begin/exception مستقل
--  — لو اتقفلت خدمة النوع ده يوم معين، باقي الرحلات المتكررة (أنواع
--  تانية) تتولّد عادي، والرحلة المحجوبة دي يتأجل توليدها (من غير
--  تحديث last_generated_date) عشان لو الخدمة اتفتحت تاني نفس اليوم
--  تتولد في أقرب تشغيل تالي للـ cron.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.generate_recurring_rides()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_dow int := extract(dow from v_today)::int;
  v_sched record;
  v_scheduled_at timestamptz;
begin
  for v_sched in
    select * from public.recurring_ride_schedules
    where active = true
      and v_dow = any(days_of_week)
      and (last_generated_date is distinct from v_today)
  loop
    v_scheduled_at := (v_today + v_sched.time_of_day) at time zone 'Africa/Cairo';

    if v_scheduled_at > now() then
      begin
        insert into public.rides (
          customer_phone, customer_name, from_area, from_lat, from_lng,
          to_area, to_lat, to_lng, distance_km, fare, eta_minutes, passengers,
          payment, status, ride_type, is_negotiable, airport_quality_tier, scheduled_at
        ) values (
          v_sched.customer_phone, v_sched.customer_name, v_sched.from_area, v_sched.from_lat, v_sched.from_lng,
          v_sched.to_area, v_sched.to_lat, v_sched.to_lng, v_sched.distance_km, v_sched.fare, v_sched.eta_minutes,
          v_sched.passengers, v_sched.payment, 'scheduled', v_sched.ride_type, v_sched.is_negotiable,
          nullif(v_sched.quality_tier, 'regular'), v_scheduled_at
        );
      exception when others then
        -- One schedule's ride-type being switched off (or any other
        -- per-row failure) must not block every other customer's
        -- recurring ride today. last_generated_date stays unset so this
        -- one retries on the next cron tick.
        raise warning 'generate_recurring_rides: skipped schedule % (%)', v_sched.id, sqlerrm;
        continue;
      end;
    end if;

    update public.recurring_ride_schedules set last_generated_date = v_today where id = v_sched.id;
  end loop;
end;
$$;
