-- =====================================================================
--  وصّلها — Security #18: إشعار فوري للتاجر عند وصول طلب جديد
--
--  نفس نمط trg_notify_drivers_new_ride الموجود في pushnotifications.sql —
--  تريجر على orders بيستدعي دالة send-push عبر pg_net فور إدراج الصف،
--  بدل ما التاجر يعتمد على الـ polling كل 5 ثواني في لوحة التحكم/التطبيق.
--  send-push بترسل Web Push (متصفح) و FCM (تطبيق التاجر على أندرويد،
--  لو device_tokens فيها توكن مسجل لرقم صاحب المتجر) مع بعض.
--
--  ⚠️ قبل تشغيل هذا الملف:
--    - دالة send-push المحدّثة (بدعم FCM) لازم تكون منشورة بالفعل
--    - pg_net لازم يكون مفعّل (اتفعّل بالفعل في pushnotifications.sql)
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.notify_merchant_new_order()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner_phone text;
  v_store_name  text;
begin
  if new.status = 'pending' and new.store_id is not null and new.store_id <> 'courier' then
    select owner_phone, name into v_owner_phone, v_store_name
    from public.stores where id = new.store_id;

    if v_owner_phone is not null then
      perform net.http_post(
        url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'x-push-secret', 'T-reW-9ouyCJ8dYAE1v4G2fEGzJwRXMaWCf1XnwIVBg',
          -- Supabase's gateway (Kong) requires an apikey on every Edge
          -- Function call regardless of the function's own "Verify JWT"
          -- setting — without it pg_net's request never reaches our code
          -- at all and gets a bare 401 from the gateway itself.
          'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
        ),
        body    := jsonb_build_object(
          'phone', v_owner_phone,
          'title', '🛎️ طلب جديد — ' || coalesce(v_store_name, ''),
          'body',  coalesce(new.items_summary, '') || ' — ' || coalesce(new.total::text, '') || ' ج.م',
          'url',   '/merchant-dashboard',
          'tag',   'wslha-order-' || new.id
        )
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_merchant_new_order on public.orders;
create trigger trg_notify_merchant_new_order
  after insert on public.orders
  for each row execute function public.notify_merchant_new_order();
