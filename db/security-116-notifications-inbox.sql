-- =====================================================================
--  وصّلها — Security #116: صندوق إشعارات داخل التطبيق (مُزامن من السيرفر)
--
--  لحد دلوقتي "سجل الإشعارات" في التطبيق (notifications_screen.dart)
--  كان بيقرا من SharedPreferences بس — سجل محلي على الجهاز، بيضيع لو
--  التطبيق اتمسح أو اتسجّل في جهاز تاني، ومافيهوش "اتقرت/لسه". كل
--  الإرسال الفعلي (push حقيقي عبر send-push) موجود وشغّال من قبل —
--  الناقص هو نسخة دائمة على السيرفر، مزامنة بين الأجهزة.
--
--  الجدول ده بيُكتب فيه من دالة send-push نفسها (service role) كل ما
--  تبعت push لشخص أو لدور كامل — مش من تريجرات متفرقة. القراءة/التحديث
--  بس عن طريق RPCs بالأسفل (نفس نمط device_tokens: لا SELECT/UPDATE
--  مباشر لـ anon، والعميل يبعت رقم تليفونه كـ parameter — نفس أسلوب
--  التوثيق المستخدم في كل المشروع، مش تغيير جديد).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  phone       text not null,
  title       text not null,
  body        text not null default '',
  url         text,
  type        text,
  tag         text,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists notifications_phone_created_idx
  on public.notifications(phone, created_at desc);
create index if not exists notifications_unread_idx
  on public.notifications(phone) where read_at is null;

alter table public.notifications enable row level security;
-- الكتابة/التحديث RPC-only (الدوال الأربعة بالأسفل + service role في
-- send-push) — بدون INSERT/UPDATE/DELETE policy لـ anon عمدًا.
-- SELECT مفتوح (using true) مش لأن المحتوى حساس وياريت نخليه مقفول،
-- لكن لأن .stream() الوحيدة طريقة فعلية لتحديث شارة العداد لحظيًا من
-- غير Supabase Auth JWT — نفس المقايضة المستخدمة فعلاً مع
-- ride_messages/ride_price_offers/driver_locations، والتطبيق بيفلتر
-- بالتليفون في طلب الـ stream نفسه (.eq('phone', phone)).
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'notifications' and policyname = 'notifications_select_open'
  ) then
    create policy notifications_select_open on public.notifications for select using (true);
  end if;
end $$;

create or replace function public.list_notifications(p_phone text, p_limit int default 50)
returns setof public.notifications
language sql
security definer
set search_path = public, extensions
as $$
  select * from public.notifications
  where phone = p_phone
  order by created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

create or replace function public.unread_notifications_count(p_phone text)
returns integer
language sql
security definer
set search_path = public, extensions
as $$
  select count(*)::int from public.notifications
  where phone = p_phone and read_at is null;
$$;

create or replace function public.mark_notification_read(p_phone text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.notifications
  set read_at = now()
  where id = p_id and phone = p_phone and read_at is null;
end;
$$;

create or replace function public.mark_all_notifications_read(p_phone text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.notifications
  set read_at = now()
  where phone = p_phone and read_at is null;
end;
$$;

grant execute on function public.list_notifications(text, int) to anon, authenticated;
grant execute on function public.unread_notifications_count(text) to anon, authenticated;
grant execute on function public.mark_notification_read(text, uuid) to anon, authenticated;
grant execute on function public.mark_all_notifications_read(text) to anon, authenticated;

-- بث لحظي: عشان شاشة الإشعارات/شارة العداد تتحدث فورًا من غير ما
-- المستخدم يعمل refresh — نفس نمط security-38/53/69.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
