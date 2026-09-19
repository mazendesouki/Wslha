-- =====================================================================
--  وصّلها — Security #83: إشعار Push عند رسالة جديدة في شات الرحلة
--
--  send_ride_message() (security-69) كانت بتسجّل الرسالة بس — الطرف
--  التاني ميعرفش إن فيه رسالة جديدة غير لو شاشة الشات نفسها مفتوحة
--  عنده فعلاً (Realtime بيشتغل بس وقت ما الشاشة مفتوحة ومشتركة). لو
--  التطبيق مقفول أو في الخلفية، الرسالة توصله من غير أي تنبيه خالص.
--
--  الحل: بعد ما الرسالة تتسجّل، الدالة بتجيب الطرف التاني (مش المرسل)
--  من صف الرحلة، وتبعتله push إشعار — نفس نمط notify_customer_ride_accepted
--  و notify_drivers_new_ride (net.http_post على send-push Edge Function).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.send_ride_message(p_ride_id uuid, p_sender_phone text, p_sender_role text, p_body text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
  v_ride record;
  v_body text := trim(p_body);
  v_recipient_phone text;
begin
  if v_body is null or length(v_body) = 0 then
    return null;
  end if;

  select * into v_ride from public.rides
   where id = p_ride_id
     and (customer_phone = p_sender_phone or driver_phone = p_sender_phone);
  if v_ride.id is null then
    raise exception 'NOT_PARTICIPANT';
  end if;

  insert into public.ride_messages(ride_id, sender_phone, sender_role, body)
  values (p_ride_id, p_sender_phone, p_sender_role, v_body)
  returning id into v_id;

  v_recipient_phone := case
    when v_ride.customer_phone = p_sender_phone then v_ride.driver_phone
    else v_ride.customer_phone
  end;

  if v_recipient_phone is not null then
    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-push-secret', public._push_trigger_secret(),
        'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
      ),
      body    := jsonb_build_object(
        'phone', v_recipient_phone,
        'title', '💬 رسالة جديدة',
        'body',  v_body,
        'url',   '/rides',
        'tag',   'wslha-ride-chat-' || p_ride_id
      )
    );
  end if;

  return v_id;
end;
$$;

grant execute on function public.send_ride_message(uuid, text, text, text) to anon, authenticated;
