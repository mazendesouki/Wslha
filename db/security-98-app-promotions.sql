-- ═══════════════════════════════════════════════════════════════
-- Admin tool: send an in-app popup notification (offer/announcement) —
-- optional emoji + optional horizontal image (1080×566 recommended),
-- shown for a fixed display duration (auto-dismisses) or closed early
-- via an X button, targeted at all/customer/driver/merchant, active
-- within an admin-set [starts_at, ends_at] window.
--
-- RLS enabled with NO policies — same narrow-RPC pattern as driver_
-- locations (security-91's comment) — only SECURITY DEFINER functions
-- touch this table, nothing is directly selectable/writable by anon.
--
-- Verified live (test rows created + cleaned up): admin_create/list/end/
-- delete_promotion and get_active_promotion all round-tripped correctly,
-- including target filtering ('driver'-targeted promo hidden from
-- get_active_promotion('customer') but shown for 'driver').
-- ═══════════════════════════════════════════════════════════════
set search_path = public, extensions;

create table if not exists public.app_promotions (
  id text primary key default 'promo-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
  message text not null,
  emoji text,
  image_url text,
  target text not null default 'all' check (target in ('all', 'customer', 'driver', 'merchant')),
  display_seconds integer not null default 8 check (display_seconds > 0),
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  active boolean not null default true,
  created_by text,
  created_at timestamptz not null default now()
);
alter table public.app_promotions enable row level security;

-- ── admin: create ──
create or replace function public.admin_create_promotion(
  p_admin_phone text, p_admin_password text,
  p_message text, p_emoji text, p_image_url text,
  p_target text, p_display_seconds integer, p_ends_at timestamptz
)
returns app_promotions
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare v_admin record; v_row public.app_promotions;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_password';
  end if;

  if p_message is null or length(trim(p_message)) = 0 then raise exception 'message_required'; end if;
  if p_ends_at is null or p_ends_at <= now() then raise exception 'invalid_ends_at'; end if;

  insert into public.app_promotions (message, emoji, image_url, target, display_seconds, ends_at, created_by)
  values (
    trim(p_message), nullif(trim(coalesce(p_emoji, '')), ''), nullif(trim(coalesce(p_image_url, '')), ''),
    coalesce(p_target, 'all'), coalesce(p_display_seconds, 8), p_ends_at, v_admin.phone
  )
  returning * into v_row;

  return v_row;
end;
$function$;
grant execute on function public.admin_create_promotion(text, text, text, text, text, text, integer, timestamptz) to anon, authenticated;

-- ── admin: list (management table) ──
create or replace function public.admin_list_promotions(p_admin_phone text, p_admin_password text)
returns setof app_promotions
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_password';
  end if;

  return query select * from public.app_promotions order by created_at desc limit 200;
end;
$function$;
grant execute on function public.admin_list_promotions(text, text) to anon, authenticated;

-- ── admin: end early (deactivate, keeps history) ──
create or replace function public.admin_end_promotion(p_admin_phone text, p_admin_password text, p_id text)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_password';
  end if;

  update public.app_promotions set active = false where id = p_id;
  return found;
end;
$function$;
grant execute on function public.admin_end_promotion(text, text, text) to anon, authenticated;

-- ── admin: delete (full cleanup) ──
create or replace function public.admin_delete_promotion(p_admin_phone text, p_admin_password text, p_id text)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_password';
  end if;

  delete from public.app_promotions where id = p_id;
  return found;
end;
$function$;
grant execute on function public.admin_delete_promotion(text, text, text) to anon, authenticated;

-- ── app: the one active promotion for this audience, if any ──
create or replace function public.get_active_promotion(p_target text)
returns app_promotions
language sql
stable
security definer
set search_path = public, extensions
as $$
  select * from public.app_promotions
  where active = true
    and starts_at <= now() and ends_at >= now()
    and (target = 'all' or target = p_target)
  order by created_at desc
  limit 1;
$$;
grant execute on function public.get_active_promotion(text) to anon, authenticated;
