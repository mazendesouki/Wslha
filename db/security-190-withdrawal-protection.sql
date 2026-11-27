-- security-190: real withdrawal protection (rate limit + large-amount review gate)
-- آمن لإعادة التشغيل (idempotent) — safe to re-run.
--
-- Context: request_withdrawal() debits the wallet immediately on a
-- correct account password, with no rate limit and no cap — a
-- compromised password (phishing, credential reuse, a stolen/unlocked
-- phone) lets an attacker drain the full balance in one call. This is
-- the actual risk behind "large sums withdrawn from the balance"; it has
-- nothing to do with the Supabase anon/publishable key visible in a
-- browser's F12 panel, which is meant to be public and carries no power
-- on its own — every sensitive table in this project is already locked
-- down so that key alone can't read or move money (see the many
-- security-*-lockdown migrations). What actually protects balances is
-- what this migration adds:
--
-- 1. A rate limit on withdrawal attempts (reuses the generic
--    _rate_limit_hit from security-186).
-- 2. Any single withdrawal above app_settings.large_withdrawal_threshold
--    no longer debits the wallet immediately — it's held as
--    'pending_review' with nothing yet removed from the balance, and
--    needs an explicit admin approval (admin_approve_withdrawal) before
--    the money actually leaves. Rejecting one (admin_reject_withdrawal)
--    costs the customer nothing since no balance change ever happened.
--    Withdrawals at or under the threshold behave exactly as before —
--    instant, no new friction for normal use.

insert into public.app_settings (key, value)
values ('large_withdrawal_threshold', '3000')
on conflict (key) do nothing;

create or replace function public.request_withdrawal(
  p_phone text,
  p_amount numeric,
  p_dest text,
  p_password text,
  p_note text default null
)
returns wallet_requests
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_acct public.accounts%rowtype;
  v_bal numeric;
  v_row public.wallet_requests;
  v_amt numeric := round(p_amount::numeric, 2);
  v_threshold numeric := public._pricing_setting_num('large_withdrawal_threshold', 3000, 0);
begin
  if not public._rate_limit_hit('withdrawal_request:' || coalesce(p_phone, ''), 5, 300) then
    raise exception 'too many withdrawal attempts, please wait a few minutes' using errcode = 'P0001';
  end if;

  select * into v_acct from public.accounts where phone = p_phone limit 1;
  if v_acct.phone is null or v_acct.password is null
     or v_acct.password <> extensions.crypt(p_password, v_acct.password) then
    raise exception 'invalid_credentials';
  end if;

  if v_amt is null or v_amt < 10 then raise exception 'amount_too_small'; end if;
  if p_dest is null or length(trim(p_dest)) = 0 then raise exception 'destination_required'; end if;

  select balance into v_bal from public.wallets where phone = p_phone for update;
  if v_bal is null then v_bal := 0; end if;
  if v_amt > v_bal then raise exception 'insufficient_funds'; end if;

  if v_amt > v_threshold then
    -- Large withdrawal: hold for admin review, nothing debited yet.
    insert into public.wallet_requests (id, phone, kind, amount, destination, note, status)
    values ('wd-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,6),
            p_phone, 'withdrawal', v_amt, p_dest, p_note, 'pending_review')
    returning * into v_row;
    return v_row;
  end if;

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
$function$;

create or replace function public.admin_approve_withdrawal(p_admin_phone text, p_admin_password text, p_request_id text)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_req public.wallet_requests%rowtype;
  v_bal numeric;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  select * into v_req from public.wallet_requests
    where id = p_request_id and kind = 'withdrawal' and status = 'pending_review'
    for update;
  if v_req.id is null then return false; end if;

  -- Re-check funds at approval time — the balance could have moved since
  -- the request was made (another withdrawal, a refund, etc).
  select balance into v_bal from public.wallets where phone = v_req.phone for update;
  if v_bal is null or v_req.amount > v_bal then
    update public.wallet_requests set status = 'rejected', processed_at = now(),
      note = coalesce(note || ' — ', '') || 'رُفض تلقائيًا: الرصيد غير كافٍ وقت المراجعة'
      where id = p_request_id;
    return false;
  end if;

  update public.wallets set balance = balance - v_req.amount, updated_at = now() where phone = v_req.phone;

  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values ('wtx-w-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,5),
          v_req.phone, -v_req.amount, 'withdrawal',
          coalesce(nullif(trim(v_req.note),''),'سحب رصيد') || ' — إلى ' || v_req.destination, now());

  update public.wallet_requests set status = 'approved', processed_at = now() where id = p_request_id;
  return true;
end;
$function$;

create or replace function public.admin_reject_withdrawal(p_admin_phone text, p_admin_password text, p_request_id text, p_reason text default null)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  update public.wallet_requests
     set status = 'rejected', processed_at = now(),
         note = coalesce(note || ' — ', '') || coalesce(nullif(trim(p_reason), ''), 'مرفوض من الإدارة')
   where id = p_request_id and kind = 'withdrawal' and status = 'pending_review';

  return found;
end;
$function$;

create or replace function public.admin_list_pending_withdrawals(p_admin_phone text, p_admin_password text)
returns setof wallet_requests
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;
  return query select * from public.wallet_requests
    where kind = 'withdrawal' and status = 'pending_review'
    order by created_at asc;
end;
$function$;
