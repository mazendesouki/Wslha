-- =====================================================================
--  وصّلها — Security #21: إشعار فوري للسائق عند وصول عرض رحلة/توصيل جديد
--
--  السائق كان بيعتمد على polling كل 5 ثواني (get_my_pending_offer) عشان
--  يشوف عروض الديسباتش الجديدة — ده بيسبب تأخير محسوس (لحد 5 ثواني) قبل
--  ما شاشة العرض تظهر عنده، وده بيتضاعف بتأخير قبول/رفض السائق فبيتأخر
--  وصول الرد للعميل. نفس نمط trg_notify_merchant_new_order
--  (security-18) — تريجر على dispatch_offers بيستدعي send-push فور
--  الإدراج، والتطبيق (PushRegistrar.onMessage) بيرد فورًا بفحص العرض
--  تاني من غير ما يستنى الـ poll التالي.
--
--  ⚠️ قبل تشغيل هذا الملف:
--    - دالة send-push المحدّثة (بدعم type/channel) لازم تكون منشورة بالفعل
--    - pg_net لازم يكون مفعّل
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.notify_driver_new_offer()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.status = 'pending' and new.driver_phone is not null then
    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-push-secret', public._push_trigger_secret(),
        'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
      ),
      body    := jsonb_build_object(
        'phone',   new.driver_phone,
        'title',   case when new.target_type = 'order' then '📦 طلب توصيل جديد' else '🚖 رحلة جديدة' end,
        'body',    'اضغط بسرعة قبل ما ينتهي العرض',
        'url',     '/driver-dashboard',
        'tag',     'wslha-offer-' || new.id,
        'type',    'dispatch_offer',
        'channel', 'wslha_rides'
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_driver_new_offer on public.dispatch_offers;
create trigger trg_notify_driver_new_offer
  after insert on public.dispatch_offers
  for each row execute function public.notify_driver_new_offer();
