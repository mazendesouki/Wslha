-- =====================================================================
--  وصّلها — إشعارات Push حقيقية للسائقين (تصل حتى والتطبيق مقفول)
--
--  الأجزاء:
--  1) فهرس فريد + سياسات RLS لجدول push_subscriptions (اشتراك المتصفح)
--  2) تريجر على rides: أي رحلة جديدة → استدعاء دالة send-push عبر pg_net
--
--  ⚠️ قبل تشغيل هذا الملف:
--    - انشر دالة send-push (خطوات النشر في رسالتي)
--    - فعّل امتداد pg_net من Database → Extensions لو مش مفعّل
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create extension if not exists pg_net;

-- 1) اشتراك واحد لكل (رقم، دور) — عشان upsert من المتصفح يشتغل
create unique index if not exists push_subscriptions_phone_role_key
  on public.push_subscriptions (phone, role);

drop policy if exists push_subs_insert_own on public.push_subscriptions;
create policy push_subs_insert_own on public.push_subscriptions
  for insert to anon, authenticated with check (true);
drop policy if exists push_subs_update_own on public.push_subscriptions;
create policy push_subs_update_own on public.push_subscriptions
  for update to anon, authenticated using (true) with check (true);
drop policy if exists push_subs_delete_own on public.push_subscriptions;
create policy push_subs_delete_own on public.push_subscriptions
  for delete to anon, authenticated using (true);
-- ملاحظة: بلا سياسة SELECT — محتوى الاشتراكات (endpoints) لا يُقرأ من العميل؛
-- دالة send-push بتقرأه بمفتاح service_role اللي بيتجاوز RLS.

-- 2) تريجر إشعار السائقين عند إنشاء رحلة جديدة
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
        'x-push-secret', 'VlLLnM4NmT8Azxrjvp9ph0oziju4AXxr'
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

drop trigger if exists trg_notify_drivers_new_ride on public.rides;
create trigger trg_notify_drivers_new_ride
  after insert on public.rides
  for each row execute function public.notify_drivers_new_ride();
