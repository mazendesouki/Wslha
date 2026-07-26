-- =====================================================================
--  وصّلها — Security #4: تسجيل توكن الإشعارات (FCM) بأمان
--
--  الجدول يخزّن توكن كل جهاز مسجّل دخول، عشان دالة send-push (لما تتوسّع
--  لدعم FCM native جنب الـ Web Push الحالي) تعرف تبعت للتطبيق المثبّت.
--  الكتابة تتم فقط عبر upsert_device_token (security definer) — العميل
--  ميقدرش يعمل INSERT/UPDATE مباشر على الجدول.
--
--  Run once in the Supabase SQL Editor. Idempotent — safe to re-run.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.device_tokens (
  id          text primary key,
  phone       text not null,
  token       text not null,
  platform    text not null check (platform in ('android','ios')),
  updated_at  timestamptz not null default now(),
  unique (phone, token)
);
create index if not exists device_tokens_phone_idx on public.device_tokens(phone);

alter table public.device_tokens enable row level security;
-- No SELECT/INSERT/UPDATE policies for anon/authenticated — all access
-- goes through the security-definer RPC below (or the service role).

create or replace function public.upsert_device_token(
  p_phone text, p_token text, p_platform text
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_phone is null or length(trim(p_phone)) = 0 then
    raise exception 'رقم الهاتف مطلوب';
  end if;
  if p_token is null or length(trim(p_token)) = 0 then
    raise exception 'التوكن مطلوب';
  end if;
  if p_platform not in ('android','ios') then
    raise exception 'منصة غير معروفة: %', p_platform;
  end if;

  insert into public.device_tokens (id, phone, token, platform, updated_at)
  values ('dt-' || substr(md5(p_phone || p_token), 1, 24), p_phone, p_token, p_platform, now())
  on conflict (phone, token)
  do update set platform = excluded.platform, updated_at = now();
end;
$$;

grant execute on function public.upsert_device_token(text, text, text) to anon, authenticated;
