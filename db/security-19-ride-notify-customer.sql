-- =====================================================================
--  وصّلها — Security #19: إشعار فوري للعميل لما سائق يقبل رحلته
--
--  نفس نمط security-18 (إشعار التاجر بطلب جديد) بس في الاتجاه التاني:
--  تريجر على rides بيستدعي send-push فور ما driver_phone يتظبط لأول
--  مرة (يعني رحلة كانت من غير سائق وبقى ليها سائق)، برقم العميل.
--
--  ⚠️ قبل تشغيل هذا الملف:
--    - دالة send-push المحدّثة (بدعم FCM) لازم تكون منشورة بالفعل
--    - pg_net لازم يكون مفعّل (اتفعّل بالفعل في pushnotifications.sql)
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.notify_customer_ride_accepted()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if old.driver_phone is null and new.driver_phone is not null and new.customer_phone is not null then
    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-push-secret', 'VlLLnM4NmT8Azxrjvp9ph0oziju4AXxr'
      ),
      body    := jsonb_build_object(
        'phone', new.customer_phone,
        'title', '🚗 السائق في الطريق!',
        'body',  coalesce(new.driver_name, 'السائق') || ' قبل رحلتك — ' ||
                 coalesce(new.from_area, '') || ' ← ' || coalesce(new.to_area, ''),
        'url',   '/rides',
        'tag',   'wslha-ride-accepted-' || new.id
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_customer_ride_accepted on public.rides;
create trigger trg_notify_customer_ride_accepted
  after update on public.rides
  for each row execute function public.notify_customer_ride_accepted();
