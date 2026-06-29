-- ════════════════════════════════════════════════════════════════
-- وصّلها — Security fix #1: hash passwords + server-side login
-- Run ONCE in Supabase → SQL Editor.
-- On Supabase, pgcrypto lives in the `extensions` schema → call its
-- functions as extensions.crypt() / extensions.gen_salt().
-- Safe & idempotent: verify_login matches bcrypt OR legacy plaintext,
-- so there is no login-lockout window. Re-runnable.
-- ════════════════════════════════════════════════════════════════

-- 1) Hashing engine
create extension if not exists pgcrypto with schema extensions;

-- 2) Auto-hash any password written to accounts (only if still plaintext)
create or replace function public.hash_account_password()
returns trigger
language plpgsql
set search_path = public, extensions as $$
begin
  if new.password is not null
     and left(new.password, 4) not in ('$2a$', '$2b$', '$2y$') then
    new.password := extensions.crypt(new.password, extensions.gen_salt('bf'));
  end if;
  return new;
end; $$;

drop trigger if exists trg_hash_account_password on public.accounts;
create trigger trg_hash_account_password
  before insert or update of password on public.accounts
  for each row execute function public.hash_account_password();

-- 3) Migrate existing plaintext passwords to bcrypt (one-time, idempotent)
update public.accounts
   set password = extensions.crypt(password, extensions.gen_salt('bf'))
 where password is not null
   and left(password, 4) not in ('$2a$', '$2b$', '$2y$');

-- 4) Server-side login — returns the account WITHOUT the password.
create or replace function public.verify_login(p_phone text, p_password text)
returns table (
  phone text, name text, username text, email text,
  role text, status text, city text, created_at timestamptz
)
language sql
security definer
set search_path = public, extensions as $$
  select a.phone, a.name, a.username, a.email, a.role, a.status, a.city, a.created_at
  from public.accounts a
  where (
        a.phone = p_phone
     or a.phone = case when p_phone like '+2%' then substr(p_phone, 3) else '+2' || p_phone end
  )
  and (
        a.password = extensions.crypt(p_password, a.password)
     or a.password = p_password
  )
  limit 1;
$$;

grant execute on function public.verify_login(text, text) to anon;

-- OPTIONAL later (after code deployed & login confirmed):
--   revoke select (password) on public.accounts from anon;
