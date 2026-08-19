-- =====================================================================
--  وصّلها — Security #25: نقل PUSH_TRIGGER_SECRET لـ Supabase Vault
--
--  السر ده كان متكتوب صريح (نص عادي) جوه 4 ملفات SQL متبعتة على GitHub
--  publicly (security-18/19/21 + pushnotifications.sql) — أي حد يشوف
--  الـ repo كان يقدر يقرأه وينادي دالة send-push بنفسه (يبعت إشعارات
--  مزيفة لأي رقم مسجّل). تدوير السر لوحده مش كفاية لأن أي نسخة جديدة
--  هتتكتب برضه صريحة في كود بيتنشر — الحل الصح إن السر يتخزن في
--  Supabase Vault (مشفّر، مايظهرش في أي ملف SQL) والتريجرز تقرأه وقت
--  التنفيذ بس عن طريق الدالة _push_trigger_secret() تحت.
--
--  ⚠️ قبل تشغيل الملف ده، لازم أول حاجة تشغّل الأمر ده *لوحده* في
--  SQL Editor (بالقيمة اللي بعتهالك في الشات، مش من هنا) — ده تخزين
--  السر في Vault، ومحتاج يتشغل مرة واحدة بس، وميتحطش في أي ملف بيتبعت
--  لأي حتة:
--
--    select vault.create_secret('<القيمة اللي بعتهالك في الشات>', 'push_trigger_secret');
--
--  لو شغّلته قبل كده وعايز تغيّر القيمة تاني:
--
--    select vault.update_secret(
--      (select id from vault.secrets where name = 'push_trigger_secret'),
--      '<القيمة الجديدة>'
--    );
--
--  بعد كده، وبعد ما تحدّث نفس القيمة في Edge Function secret
--  (PUSH_TRIGGER_SECRET) من Supabase Dashboard، شغّل باقي الملف ده.
-- =====================================================================
set search_path = public, extensions;

create or replace function public._push_trigger_secret()
returns text
language sql
stable
security definer
set search_path = public, extensions, vault
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'push_trigger_secret' limit 1;
$$;

revoke all on function public._push_trigger_secret() from public, anon, authenticated;

-- ── إعادة تعريف كل التريجرز الأربعة عشان تستخدم الدالة دي بدل النص الصريح ──

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
          'x-push-secret', public._push_trigger_secret(),
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
        'x-push-secret', public._push_trigger_secret(),
        'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
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

create or replace function public.notify_drivers_new_ride()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.status = 'pending' and new.driver_phone is null then
    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-push-secret', public._push_trigger_secret(),
        'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
      ),
      body    := jsonb_build_object(
        'target', 'driver',
        'title',  '🚗 طلب رحلة جديد!',
        'body',   coalesce(new.from_area, '') || ' ← ' || coalesce(new.to_area, '') || ' — ' || coalesce(new.fare::text, '') || ' ج.م',
        'url',    '/driver-dashboard',
        'tag',    'wslha-ride-' || new.id
      )
    );
  end if;
  return new;
end;
$$;

-- التريجرز نفسها موجودة بالفعل (create or replace function بس عدّل
-- المنطق جوه — مفيش داعي نعيد drop/create trigger).
