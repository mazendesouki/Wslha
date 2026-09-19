-- =====================================================================
--  وصّلها — Security #76: جدولة رحلة مسبقًا
--
--  العميل يقدر يحجز مشوار لميعاد لاحق بدل الحجز الفوري بس. الرحلة
--  بتتسجّل بحالة 'scheduled' (عمود جديد scheduled_at) فمفيش أي سائق
--  بيشوفها ولا بيتبعتله إشعار — الـ triggers الحالية اللي بتوزّع
--  الرحلات وتنبّه السائقين (trg_dispatch_ride / trg_notify_drivers_new_ride)
--  بتتفعّل بس لما status = 'pending'، فرحلة 'scheduled' بتتجاهل تلقائيًا
--  من غير أي تعديل عليهم.
--
--  قريب من ميعاد الرحلة (افتراضيًا 20 دقيقة قبلها، قابل للتعديل من
--  لوحة التحكم)، Job مجدول بـ pg_cron (شغال بالفعل في المشروع ده —
--  dispatch-sweep-expired) بيحوّل حالتها لـ 'pending' ويستدعي بالظبط
--  نفس اللي بيحصل عادي لرحلة جديدة: dispatch_find_and_offer (زي
--  trg_dispatch_ride) + إشعار push للسائقين (زي notify_drivers_new_ride)
--  — بدون أي لمسة لمنطق التوزيع أو حساب الأجرة نفسه.
--
--  الإنشاء: rides مفتوح للـ INSERT أصلاً (rides_insert_all, check true —
--  نفس نموذج الثقة "معرف صعب التخمين" المستخدم في كل الجدول ده)، فمفيش
--  داعي لدالة جديدة للحجز — بس status: 'scheduled' + scheduled_at بدل
--  الحجز الفوري العادي.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.rides add column if not exists scheduled_at timestamptz;

insert into public.app_settings (key, value) values
  ('scheduled_ride_lead_minutes', '20'),
  ('feature_scheduled_rides_enabled', 'true')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- العميل يلغي رحلة لسه 'scheduled' (قبل ما تتفعّل وتتبعت لسواقين).
-- ---------------------------------------------------------------------
create or replace function public.cancel_scheduled_ride(p_ride_id uuid, p_customer_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_ride record;
begin
  select * into v_ride from public.rides where id = p_ride_id for update;
  if v_ride.id is null then return false; end if;
  if v_ride.customer_phone is distinct from p_customer_phone then return false; end if;
  if v_ride.status <> 'scheduled' then return false; end if;

  update public.rides set status = 'cancelled' where id = p_ride_id;
  return true;
end;
$$;
grant execute on function public.cancel_scheduled_ride(uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Job مجدول: كل دقيقة يفعّل أي رحلة 'scheduled' قرّب ميعادها.
-- ---------------------------------------------------------------------
create or replace function public.activate_scheduled_rides()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_lead int; v_ride record;
begin
  v_lead := public._pricing_setting_num('scheduled_ride_lead_minutes', 20, 0)::int;

  for v_ride in
    update public.rides
       set status = 'pending'
     where status = 'scheduled'
       and scheduled_at is not null
       and scheduled_at <= now() + (v_lead || ' minutes')::interval
    returning *
  loop
    if v_ride.driver_phone is null then
      perform public.dispatch_find_and_offer('ride', v_ride.id::text, v_ride.from_lat, v_ride.from_lng);
      perform net.http_post(
        url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'x-push-secret', public._push_trigger_secret(),
          'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
        ),
        body    := jsonb_build_object(
          'target', 'driver',
          'title',  '🚗 طلب رحلة مجدولة جاهزة!',
          'body',   coalesce(v_ride.from_area, '') || ' ← ' || coalesce(v_ride.to_area, '') || ' — ' || coalesce(v_ride.fare::text, '') || ' ج.م',
          'url',    '/driver-dashboard',
          'tag',    'wslha-ride-' || v_ride.id
        )
      );
    end if;
  end loop;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'activate-scheduled-rides';
select cron.schedule('activate-scheduled-rides', '* * * * *', $$select public.activate_scheduled_rides();$$);
