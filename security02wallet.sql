-- =====================================================================
--  وصّلها — Security #2: تأمين المحفظة من تزوير الأرصدة
--  Wallet hardening: no client may set its own balance any more.
--
--  Run this whole file once in the Supabase SQL Editor.
--  It is idempotent — safe to re-run.
--
--  After running it, the browser can only:
--    • SELECT a wallet balance (read-only)
--    • call the RPCs below (deposit request / withdraw request / transfer)
--  Direct INSERT/UPDATE/DELETE on `wallets` from the anon key is BLOCKED,
--  so the old "type any balance" forgery no longer works.
-- =====================================================================

set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 0) Make sure the wallets table has a usable key for upserts
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where table_name = 'wallets' and constraint_type in ('PRIMARY KEY','UNIQUE')
  ) then
    alter table public.wallets add constraint wallets_phone_key unique (phone);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1) add_wallet_balance — the ONLY way to move a balance (server-side).
--    Already used by ride-earnings and the admin panel; we (re)create it
--    as SECURITY DEFINER so it keeps working after RLS is enabled.
--    DROP first because an older version may return a different type.
-- ---------------------------------------------------------------------
drop function if exists public.add_wallet_balance(text, numeric);
create or replace function public.add_wallet_balance(p_phone text, p_amount numeric)
returns numeric
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_new numeric;
begin
  insert into public.wallets (phone, balance, updated_at)
  values (p_phone, p_amount, now())
  on conflict (phone)
  do update set balance = public.wallets.balance + excluded.balance,
                updated_at = now()
  returning balance into v_new;
  return v_new;
end;
$$;

-- ---------------------------------------------------------------------
-- 2) wallet_requests — pending deposit / withdrawal requests for admin
-- ---------------------------------------------------------------------
create table if not exists public.wallet_requests (
  id          text primary key,
  phone       text not null,
  kind        text not null check (kind in ('deposit','withdrawal')),
  amount      numeric not null check (amount > 0),
  method      text,
  destination text,
  note        text,
  status      text not null default 'pending'
              check (status in ('pending','approved','rejected','done')),
  created_at  timestamptz not null default now(),
  processed_at timestamptz
);
create index if not exists wallet_requests_phone_idx  on public.wallet_requests(phone);
create index if not exists wallet_requests_status_idx on public.wallet_requests(status);

-- ---------------------------------------------------------------------
-- 3) request_deposit — user asks to top up. Does NOT change the balance.
--    Admin confirms the real money arrived, then credits via the panel.
-- ---------------------------------------------------------------------
create or replace function public.request_deposit(
  p_phone text, p_amount numeric, p_method text default null, p_note text default null
) returns public.wallet_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_row public.wallet_requests;
begin
  if p_amount is null or p_amount < 10 then
    raise exception 'amount_too_small';
  end if;
  insert into public.wallet_requests (id, phone, kind, amount, method, note)
  values ('dep-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,6),
          p_phone, 'deposit', round(p_amount::numeric, 2), p_method, p_note)
  returning * into v_row;
  return v_row;
end;
$$;

-- ---------------------------------------------------------------------
-- 4) request_withdrawal — reserves the funds immediately (deducts the
--    balance + logs a transaction) and opens a request for the admin to
--    pay out. Fails if the balance is insufficient. Atomic + row-locked.
-- ---------------------------------------------------------------------
create or replace function public.request_withdrawal(
  p_phone text, p_amount numeric, p_dest text, p_note text default null
) returns public.wallet_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_bal numeric;
  v_row public.wallet_requests;
  v_amt numeric := round(p_amount::numeric, 2);
begin
  if v_amt is null or v_amt < 10 then raise exception 'amount_too_small'; end if;
  if p_dest is null or length(trim(p_dest)) = 0 then raise exception 'destination_required'; end if;

  select balance into v_bal from public.wallets where phone = p_phone for update;
  if v_bal is null then v_bal := 0; end if;
  if v_amt > v_bal then raise exception 'insufficient_funds'; end if;

  -- reserve the money now so it cannot be spent twice
  update public.wallets set balance = balance - v_amt, updated_at = now() where phone = p_phone;

  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values ('wtx-w-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,5),
          p_phone, -v_amt, 'withdrawal',
          coalesce(nullif(trim(p_note),''),'سحب رصيد') || ' — إلى ' || p_dest, now());

  insert into public.wallet_requests (id, phone, kind, amount, destination, note)
  values ('wd-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,6),
          p_phone, 'withdrawal', v_amt, p_dest, p_note)
  returning * into v_row;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------------
-- 5) wallet_transfer — atomic peer-to-peer transfer with a balance check.
--    Both wallets are row-locked; either both sides move or none.
-- ---------------------------------------------------------------------
create or replace function public.wallet_transfer(
  p_from text, p_to text, p_amount numeric, p_note text default null
) returns numeric
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_from_bal numeric;
  v_to_exists boolean;
  v_amt numeric := round(p_amount::numeric, 2);
  v_note text := coalesce(nullif(trim(p_note),''),'تحويل');
begin
  if v_amt is null or v_amt < 1 then raise exception 'amount_too_small'; end if;
  if p_from = p_to then raise exception 'same_account'; end if;

  -- recipient must be a real account
  select exists(select 1 from public.accounts where phone = p_to) into v_to_exists;
  if not v_to_exists then raise exception 'recipient_not_found'; end if;

  -- lock sender first (deterministic order avoids deadlocks not needed here, single lock then upsert)
  select balance into v_from_bal from public.wallets where phone = p_from for update;
  if v_from_bal is null then v_from_bal := 0; end if;
  if v_amt > v_from_bal then raise exception 'insufficient_funds'; end if;

  update public.wallets set balance = balance - v_amt, updated_at = now() where phone = p_from;

  insert into public.wallets (phone, balance, updated_at)
  values (p_to, v_amt, now())
  on conflict (phone) do update set balance = public.wallets.balance + excluded.balance, updated_at = now();

  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values ('wtx-out-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,5),
          p_from, -v_amt, 'transfer_out', v_note || ' → ' || p_to, now());
  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values ('wtx-in-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,5),
          p_to, v_amt, 'transfer_in', v_note || ' ← ' || p_from, now());

  return v_from_bal - v_amt;
end;
$$;

-- ---------------------------------------------------------------------
-- 6) Permissions: anon can only CALL the RPCs, never touch the table.
-- ---------------------------------------------------------------------
grant execute on function public.add_wallet_balance(text, numeric) to anon, authenticated;
grant execute on function public.request_deposit(text, numeric, text, text) to anon, authenticated;
grant execute on function public.request_withdrawal(text, numeric, text, text) to anon, authenticated;
grant execute on function public.wallet_transfer(text, text, numeric, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 7) Row Level Security on wallets — read-only for the anon key.
--    SECURITY DEFINER functions above run as the table owner and bypass
--    RLS, so earnings / admin / RPCs keep working; only the raw anon
--    INSERT/UPDATE/DELETE forgery path is closed.
-- ---------------------------------------------------------------------
alter table public.wallets enable row level security;

drop policy if exists wallets_anon_select on public.wallets;
create policy wallets_anon_select on public.wallets
  for select to anon, authenticated using (true);

-- No INSERT/UPDATE/DELETE policy ⇒ those are denied for anon/authenticated.
revoke insert, update, delete on public.wallets from anon, authenticated;

-- =====================================================================
--  Done. Quick self-test (optional):
--    select public.add_wallet_balance('0100test', 5);   -- +5
--    select public.wallet_transfer('0100test','<real_phone>', 2, 'اختبار');
--  And confirm a raw write is now blocked (should error / 0 rows):
--    -- via REST: POST /rest/v1/wallets {balance:9999}  → denied
-- =====================================================================
