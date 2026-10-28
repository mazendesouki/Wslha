-- =====================================================================
--  وصّلها — Security #136: مشكلة عدم رد السائق على شات الرحلة
--
--  send_ride_message() كانت بتقارن p_sender_phone بـ rides.customer_phone
--  /driver_phone بمساواة نصية مباشرة ("=")، من غير أي تطبيع لصيغة الرقم
--  (01xxxxxxxxx مقابل +20xxxxxxxxx) — وده النمط اللي كل RPC تقريبًا في
--  المشروع بيعمله ماعدا الدالة دي. أرقام السائقين والعملاء مخزّنة فعليًا
--  بصيغتين مختلفتين في جدول rides نفسه (تأكدنا بالاستعلام المباشر).
--
--  النتيجة: لو السائق مسجّل في التطبيق برقمه بصيغة مختلفة عن اللي
--  اتخزنت في rides.driver_phone وقت قبول الرحلة، send_ride_message()
--  كانت بترفض أي رسالة منه بـ NOT_PARTICIPANT — يعني السائق فعليًا
--  مايقدرش يرد على العميل، بالظبط المشكلة المبلّغ عنها. تأكدنا حيًّا
--  (معاملة اترجعت): رسالة من سائق برقم +20 لرحلة متخزنة بصيغة 0 اترفضت
--  بنفس الخطأ ده بالظبط.
--
--  الحل: نفس نمط تطبيع الرقم (+20/0) المستخدم في كل مكان تاني في
--  المشروع، بدل المساواة المباشرة.
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
  v_sender_variants text[];
begin
  if v_body is null or length(v_body) = 0 then
    return null;
  end if;

  v_sender_variants := array[
    p_sender_phone,
    case when p_sender_phone like '+20%' then '0'||substr(p_sender_phone,4) else p_sender_phone end,
    case when p_sender_phone like '0%'   then '+2'||p_sender_phone           else p_sender_phone end
  ];

  select * into v_ride from public.rides
   where id = p_ride_id
     and (customer_phone = any(v_sender_variants) or driver_phone = any(v_sender_variants));
  if v_ride.id is null then
    raise exception 'NOT_PARTICIPANT';
  end if;

  insert into public.ride_messages(ride_id, sender_phone, sender_role, body)
  values (p_ride_id, p_sender_phone, p_sender_role, v_body)
  returning id into v_id;

  v_recipient_phone := case
    when v_ride.customer_phone = any(v_sender_variants) then v_ride.driver_phone
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
