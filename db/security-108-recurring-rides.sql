-- =====================================================================
--  وصّلها — Security #108: حجز رحلات متكررة ثابتة
--
--  العميل اللي بيعمل نفس الرحلة بانتظام (بيت ← شغل كل يوم الساعة 8
--  الصبح مثلاً) مكانش عنده غير إنه يحجزها يدويًا كل مرة. الحل: "قالب"
--  رحلة متكررة (أيام الأسبوع + الميعاد + المسار) بيتسجّل مرة واحدة،
--  وJob يومي بـ pg_cron بيولّد منه رحلة فعلية في جدول rides بنفس آلية
--  الرحلة المجدولة الموجودة بالفعل (security-76) — يعني نفس pipeline
--  التفعيل/التوزيع/الإشعار من غير أي لمسة له.
--
--  الجدول زي أي جدول حساس تاني (coupons/wallets/...): مفيش قراءة/كتابة
--  مباشرة، كل حاجة عن طريق دوال بيتحقق فيها من رقم هاتف العميل.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.recurring_ride_schedules (
  id uuid primary key default gen_random_uuid(),
  customer_phone text not null,
  customer_name text not null,
  from_area text not null,
  from_lat double precision not null,
  from_lng double precision not null,
  to_area text not null,
  to_lat double precision not null,
  to_lng double precision not null,
  distance_km numeric not null,
  fare numeric not null,
  eta_minutes int not null,
  passengers int not null default 1,
  payment text not null default 'cash',
  ride_type text not null default 'local',
  is_negotiable boolean not null default false,
  quality_tier text,
  -- 0=Sunday..6=Saturday, matching Postgres extract(dow)
  days_of_week int[] not null,
  time_of_day time not null,
  active boolean not null default true,
  last_generated_date date,
  created_at timestamptz not null default now()
);

alter table public.recurring_ride_schedules enable row level security;
revoke all on public.recurring_ride_schedules from anon, authenticated;

insert into public.app_settings (key, value) values
  ('feature_recurring_rides_enabled', 'true')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- إنشاء قالب رحلة متكررة.
-- ---------------------------------------------------------------------
create or replace function public.create_recurring_ride_schedule(
  p_customer_phone text,
  p_customer_name text,
  p_from_area text,
  p_from_lat double precision,
  p_from_lng double precision,
  p_to_area text,
  p_to_lat double precision,
  p_to_lng double precision,
  p_distance_km numeric,
  p_fare numeric,
  p_eta_minutes int,
  p_passengers int,
  p_payment text,
  p_days_of_week int[],
  p_time_of_day time,
  p_ride_type text default 'local',
  p_is_negotiable boolean default false,
  p_quality_tier text default null
) returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_id uuid;
begin
  if p_days_of_week is null or array_length(p_days_of_week, 1) is null then
    raise exception 'لازم تختار يوم واحد على الأقل';
  end if;

  insert into public.recurring_ride_schedules (
    customer_phone, customer_name, from_area, from_lat, from_lng,
    to_area, to_lat, to_lng, distance_km, fare, eta_minutes, passengers,
    payment, ride_type, is_negotiable, quality_tier, days_of_week, time_of_day
  ) values (
    p_customer_phone, p_customer_name, p_from_area, p_from_lat, p_from_lng,
    p_to_area, p_to_lat, p_to_lng, p_distance_km, p_fare, p_eta_minutes, p_passengers,
    p_payment, coalesce(p_ride_type, 'local'), coalesce(p_is_negotiable, false), p_quality_tier,
    p_days_of_week, p_time_of_day
  ) returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.create_recurring_ride_schedule(
  text, text, text, double precision, double precision, text, double precision, double precision,
  numeric, numeric, int, int, text, int[], time, text, boolean, text
) to anon, authenticated;

-- ---------------------------------------------------------------------
-- جداول العميل الحالية (نشطة فقط).
-- ---------------------------------------------------------------------
create or replace function public.list_my_recurring_schedules(p_customer_phone text)
returns setof public.recurring_ride_schedules
language sql
stable
security definer
set search_path = public, extensions
as $$
  select * from public.recurring_ride_schedules
  where customer_phone = p_customer_phone and active = true
  order by created_at desc;
$$;
grant execute on function public.list_my_recurring_schedules(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- إلغاء جدول متكرر (مايلغيش أي رحلة اتولّدت بالفعل من قبل).
-- ---------------------------------------------------------------------
create or replace function public.cancel_recurring_ride_schedule(p_schedule_id uuid, p_customer_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_row record;
begin
  select * into v_row from public.recurring_ride_schedules where id = p_schedule_id for update;
  if v_row.id is null then return false; end if;
  if v_row.customer_phone is distinct from p_customer_phone then return false; end if;

  update public.recurring_ride_schedules set active = false where id = p_schedule_id;
  return true;
end;
$$;
grant execute on function public.cancel_recurring_ride_schedule(uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Job يومي: لكل قالب نشط بيوم النهارده ضمن أيامه ولسه معملوش توليد
-- النهارده، يضيف رحلة 'scheduled' في rides (نفس عمود scheduled_at اللي
-- بيستخدمه security-76's activate_scheduled_rides لتفعيلها وتوزيعها
-- في وقتها بالظبط). لو الميعاد فات بالفعل النهارده (مثلاً القالب
-- اتعمل بعد الميعاد)، بيتسجّل إنه "اتعالج" النهارده من غير ما يولّد
-- رحلة — هيولّد تاني أول يوم جاي من أيام القالب.
-- ---------------------------------------------------------------------
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
    end if;

    update public.recurring_ride_schedules set last_generated_date = v_today where id = v_sched.id;
  end loop;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'generate-recurring-rides';
select cron.schedule('generate-recurring-rides', '*/15 * * * *', $$select public.generate_recurring_rides();$$);
