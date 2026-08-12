-- ═══════════════════════════════════════════════════════════════
-- Fixes: "permission denied for table accounts" (Postgres 42501) any
-- time an existing account (e.g. a customer) tries to register as a
-- driver or merchant — driver.astro, merchant-apply.astro, and the
-- Flutter native registration screen all did this the same way:
--   PATCH /rest/v1/accounts?phone=eq.X  { role: 'driver', status: 'pending' }
-- security06accountslockdown.sql revoked SELECT on accounts from
-- anon/authenticated — but PostgREST needs SELECT internally to
-- evaluate a PATCH's WHERE filter (RLS visibility check), even though
-- the operation itself is an UPDATE. So this specific "upgrade my own
-- role" path has been silently broken since that lockdown; nobody
-- noticed because most registration testing uses a brand-new phone
-- number, which goes through the (still-working) INSERT path instead.
--
-- Fix: a SECURITY DEFINER RPC, same pattern as reset_password() in
-- security-03-accounts.sql — runs with elevated privilege internally,
-- so it doesn't need the anon grant this was hitting. Hardcodes role to
-- 'driver'/'merchant' only (never 'admin') and refuses to touch an
-- existing admin account, so it can't be used for privilege escalation.
-- ═══════════════════════════════════════════════════════════════

create or replace function public.upgrade_account_role(p_phone text, p_role text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_local text;
  v_intl  text;
  v_rows  int;
begin
  if p_role not in ('driver', 'merchant') then
    raise exception 'invalid_role';
  end if;

  v_local := case when p_phone like '+20%' then '0' || substr(p_phone, 4) else p_phone end;
  v_intl  := case when p_phone like '0%'   then '+2' || p_phone           else p_phone end;

  update public.accounts
     set role = p_role, status = 'pending'
   where phone in (p_phone, v_local, v_intl)
     and role <> 'admin';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

grant execute on function public.upgrade_account_role(text, text) to anon, authenticated;
