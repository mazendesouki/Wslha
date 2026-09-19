-- =====================================================================
--  وصّلها — Security #78: رحلات المطار — إلغاء عداد العرض المؤقت +
--  تذكير قبلها بيومين بدل يوم
--
--  رحلات المطار بتتحجز مقدمًا (أحيانًا بأيام) فمفيش داعي يتحط السائق
--  تحت ضغط عداد 25-30 ثانية زي أي رحلة عادية (dispatch_offers —
--  security-21/22) — أصلاً عندهم طريق تاني بدون عداد خالص (القائمة
--  الدائمة airport_ride_requests_screen.dart، accept_airport_ride/
--  reject_airport_ride — security-65) بيقدر يقبل أو يرفض فيها في أي
--  وقت. الحل: بالظبط نفس نمط استبعاد الرحلات التفاوضية من عروض
--  الديسباتش العادية (security-36) — رحلات المطار بقت مستبعدة كمان من
--  get_my_pending_offer/get_my_pending_offers، فمفيش أي عداد هيظهر
--  للسائق عن رحلة مطار؛ القائمة الدائمة هي الطريق الوحيد بقى.
--
--  وكمان: تذكير "رحلة غدا" (security-77) بقى قبلها بيومين بدل يوم
--  واحد، بناءً على طلب صريح.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) استبعاد رحلات المطار من عروض الديسباتش المؤقتة (نفس نمط security-36).
-- ---------------------------------------------------------------------
create or replace function public.get_my_pending_offer(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer public.dispatch_offers;
  v_data  jsonb;
  v_ride_negotiable boolean;
  v_ride_type text;
begin
  select * into v_offer
  from public.dispatch_offers
  where driver_phone = p_driver_phone
    and status = 'pending'
    and expires_at > now()
  order by offered_at desc
  limit 1;

  if not found then return null; end if;

  if v_offer.target_type = 'ride' then
    select to_jsonb(r), coalesce(r.is_negotiable, false), r.ride_type into v_data, v_ride_negotiable, v_ride_type
    from public.rides r where r.id::text = v_offer.target_id;
    if v_ride_negotiable or v_ride_type = 'airport' then return null; end if;
  else
    select to_jsonb(o) into v_data from public.orders o where o.id::text = v_offer.target_id;
  end if;

  if v_data is null then return null; end if;

  return jsonb_build_object(
    'offer_id',    v_offer.id,
    'target_type', v_offer.target_type,
    'expires_at',  v_offer.expires_at,
    'data',        v_data
  );
end;
$$;

revoke all on function public.get_my_pending_offer(text) from public;
grant execute on function public.get_my_pending_offer(text) to anon, authenticated;

create or replace function public.get_my_pending_offers(p_driver_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'offer_id', d.id,
        'target_type', d.target_type,
        'expires_at', d.expires_at,
        'data', case when d.target_type = 'ride' then to_jsonb(r) else to_jsonb(ord) end
      )
      order by d.offered_at desc
    ),
    '[]'::jsonb
  ) into v_result
  from public.dispatch_offers d
  left join public.rides  r   on d.target_type = 'ride'  and r.id::text = d.target_id
  left join public.orders ord on d.target_type = 'order' and ord.id::text = d.target_id
  where d.driver_phone = p_driver_phone
    and d.status = 'pending'
    and d.expires_at > now()
    and ((d.target_type = 'ride' and r.id is not null and coalesce(r.is_negotiable, false) = false and coalesce(r.ride_type, '') <> 'airport')
         or (d.target_type = 'order' and ord.id is not null));

  return v_result;
end;
$$;

revoke all on function public.get_my_pending_offers(text) from public;
grant execute on function public.get_my_pending_offers(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) تذكير رحلات المطار: قبلها بيومين بدل يوم.
-- ---------------------------------------------------------------------
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
       and flight_time <= now() + interval '48 hours'
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
          'title', '🛫 عندك رحلة مطار قريبة',
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
          'title', '🛫 عندك رحلة مطار قريبة',
          'body',  coalesce(v_ride.from_area, '') || ' ← ' || coalesce(v_ride.to_area, ''),
          'url',   '/driver-dashboard',
          'tag',   'wslha-airport-reminder-' || v_ride.id
        )
      );
    end if;
  end loop;
end;
$$;
