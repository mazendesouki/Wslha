-- ═══════════════════════════════════════════════════════════════
-- National ID for customers + cross-role uniqueness (customer /
-- driver / merchant all share the same national_id namespace).
-- Run this whole file once in the Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════════

-- 1) New columns on accounts (customers)
alter table public.accounts add column if not exists national_id text;
alter table public.accounts add column if not exists national_id_expiry date;

-- 2) A real Postgres person can only have one customer account with
--    a given national ID (defense-in-depth on top of the app check).
create unique index if not exists accounts_national_id_uidx
  on public.accounts (national_id) where national_id is not null;

-- 3) Cross-table lookup used both by the availability RPC and by the
--    insert-time trigger guard below. Excludes rejected applications
--    so a rejected driver/merchant applicant isn't permanently locked
--    out of registering under a different role.
create or replace function public.national_id_taken_elsewhere(
  p_id          text,
  p_self_table  text default null,
  p_self_phone  text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
begin
  if p_id is null or p_id = '' then return false; end if;

  select
    exists(
      select 1 from public.accounts
      where national_id = p_id
        and (p_self_table is distinct from 'accounts' or phone is distinct from p_self_phone)
    )
    or exists(
      select 1 from public.driver_applications
      where national_id_number = p_id
        and status <> 'rejected'
        and (p_self_table is distinct from 'driver_applications' or phone is distinct from p_self_phone)
    )
    or exists(
      select 1 from public.merchant_applications
      where national_id_number = p_id
        and status <> 'rejected'
        and (p_self_table is distinct from 'merchant_applications' or phone is distinct from p_self_phone)
    )
  into v_exists;

  return coalesce(v_exists, false);
end;
$$;

revoke all on function public.national_id_taken_elsewhere(text, text, text) from public;
grant execute on function public.national_id_taken_elsewhere(text, text, text) to anon, authenticated;

-- 4) Dedicated availability RPC for national_id — deliberately NOT
--    folded into check_field_availability(p_field,p_value), since we
--    don't want to touch/guess that existing function's body for the
--    phone/email/username branches it already handles correctly.
create or replace function public.check_national_id_availability(p_value text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select not public.national_id_taken_elsewhere(p_value, null, null);
$$;

revoke all on function public.check_national_id_availability(text) from public;
grant execute on function public.check_national_id_availability(text) to anon, authenticated;

-- 5) Insert-time guard (defense against the debounce-check race):
--    reject an insert on any of the three tables if the same national
--    ID already exists on another one, with a 23505-style error so the
--    client's existing "409 = already taken" handling picks it up.
create or replace function public.guard_national_id_unique()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.national_id_taken_elsewhere(
       coalesce(new.national_id, new.national_id_number),
       tg_table_name,
       new.phone
     ) then
    raise exception 'الرقم القومي مسجّل بالفعل' using errcode = '23505';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_national_id_accounts on public.accounts;
create trigger trg_guard_national_id_accounts
  before insert or update of national_id on public.accounts
  for each row execute function public.guard_national_id_unique();

drop trigger if exists trg_guard_national_id_driver_apps on public.driver_applications;
create trigger trg_guard_national_id_driver_apps
  before insert or update of national_id_number on public.driver_applications
  for each row execute function public.guard_national_id_unique();

drop trigger if exists trg_guard_national_id_merchant_apps on public.merchant_applications;
create trigger trg_guard_national_id_merchant_apps
  before insert or update of national_id_number on public.merchant_applications
  for each row execute function public.guard_national_id_unique();
