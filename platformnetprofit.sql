-- ═══════════════════════════════════════════════════════════════
-- Platform net-profit management: audited withdrawals + a tamper-
-- proof server-computed finance summary. Additive only — does NOT
-- change how commission is logged (wallet_transactions phone='platform'
-- stays the source of truth for the running balance, so existing
-- historical data keeps working unmodified).
-- Run once in the Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════════

-- Dedicated audit trail for withdrawals — every withdrawal going forward
-- records who did it, when, how much, and the balance before/after.
create table if not exists public.platform_withdrawals (
  id             text primary key,
  admin_phone    text not null,
  admin_name     text,
  amount         numeric not null check (amount > 0),
  note           text,
  balance_before numeric not null,
  balance_after  numeric not null,
  created_at     timestamptz not null default now()
);
create index if not exists platform_withdrawals_created_idx on public.platform_withdrawals (created_at desc);
revoke all on public.platform_withdrawals from anon, authenticated;

-- Server-computed, admin-only finance summary — replaces client-side
-- re-summing in admin.astro so the numbers can't be miscalculated or
-- spoofed in the browser.
create or replace function public.get_platform_finance_summary(p_admin_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_is_admin boolean;
  v_total_revenue numeric;
  v_total_withdrawn numeric;
  v_ride numeric; v_deliv numeric; v_air numeric;
begin
  select exists(
    select 1 from public.accounts
     where role = 'admin'
       and phone in (p_admin_phone,
                     case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                     case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
  ) into v_is_admin;
  if not v_is_admin then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select coalesce(sum(amount), 0) into v_total_revenue
    from public.wallet_transactions where phone = 'platform' and type = 'commission';
  select coalesce(sum(-amount), 0) into v_total_withdrawn
    from public.wallet_transactions where phone = 'platform' and type = 'withdrawal';

  select coalesce(sum(amount), 0) into v_ride from public.wallet_transactions
    where phone = 'platform' and type = 'commission' and note ilike '%رحلة%' and note not ilike '%مطار%';
  select coalesce(sum(amount), 0) into v_deliv from public.wallet_transactions
    where phone = 'platform' and type = 'commission' and note ilike '%توصيل%';
  select coalesce(sum(amount), 0) into v_air from public.wallet_transactions
    where phone = 'platform' and type = 'commission' and note ilike '%مطار%';

  return jsonb_build_object(
    'total_revenue',   v_total_revenue,
    'total_withdrawn', v_total_withdrawn,
    'balance',          v_total_revenue - v_total_withdrawn,
    'by_type', jsonb_build_object('ride', v_ride, 'delivery', v_deliv, 'airport', v_air)
  );
end;
$$;
revoke all on function public.get_platform_finance_summary(text) from public;
grant execute on function public.get_platform_finance_summary(text) to anon, authenticated;

-- Atomic, password + action-key gated withdrawal (same security bar as
-- admin_delete_account / grant_admin — a financial mutation is at least
-- as sensitive as an account deletion).
create or replace function public.admin_withdraw_platform_profit(
  p_admin_phone text, p_admin_password text, p_action_key text,
  p_amount numeric, p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin record;
  v_balance numeric;
  v_id text;
begin
  if not public.verify_action_key(p_action_key) then
    raise exception 'مفتاح الأمان غير صحيح' using errcode = '28000';
  end if;

  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  if v_admin.phone is null or v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'كلمة مرور المشرف غير صحيحة' using errcode = '28000';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'المبلغ غير صالح';
  end if;

  select coalesce(sum(case when type = 'commission' then amount when type = 'withdrawal' then amount else 0 end), 0)
    into v_balance
    from public.wallet_transactions where phone = 'platform' and type in ('commission', 'withdrawal');

  if p_amount > v_balance then
    raise exception 'المبلغ المطلوب أكبر من الرصيد المتاح (%.2f ج.م)', v_balance;
  end if;

  v_id := 'plat-wd-' || extract(epoch from clock_timestamp())::bigint || '-' || substr(md5(random()::text), 1, 6);

  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values (v_id, 'platform', -p_amount, 'withdrawal', coalesce(p_note, 'سحب أرباح المنصة — ' || v_admin.name), now());

  insert into public.platform_withdrawals (id, admin_phone, admin_name, amount, note, balance_before, balance_after)
  values (v_id, v_admin.phone, v_admin.name, p_amount, p_note, v_balance, v_balance - p_amount);

  return jsonb_build_object('ok', true, 'balance_after', v_balance - p_amount);
end;
$$;
revoke all on function public.admin_withdraw_platform_profit(text, text, text, numeric, text) from public;
grant execute on function public.admin_withdraw_platform_profit(text, text, text, numeric, text) to anon, authenticated;

-- Withdrawal history for the dashboard.
create or replace function public.get_platform_withdrawal_history(p_admin_phone text)
returns setof public.platform_withdrawals
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.accounts
     where role = 'admin'
       and phone in (p_admin_phone,
                     case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                     case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
  ) then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  return query select * from public.platform_withdrawals order by created_at desc limit 200;
end;
$$;
revoke all on function public.get_platform_withdrawal_history(text) from public;
grant execute on function public.get_platform_withdrawal_history(text) to anon, authenticated;
