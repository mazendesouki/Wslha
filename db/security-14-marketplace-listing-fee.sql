-- ═══════════════════════════════════════════════════════════════
-- سوق المستعمل — رسم ثابت لنشر أي إعلان.
--
-- Was completely free before this — no payment/commission of any kind.
-- Extends guard_marketplace_item() (marketplaceschema.sql), the existing
-- BEFORE INSERT trigger that already normalizes seller_type/quantity/
-- status server-side, so no client code needs to change how it inserts
-- — the trigger now also charges public.wallets before letting the
-- insert through. Insufficient balance aborts the whole insert (no
-- listing created, no fee charged) via a raised exception the client
-- can pattern-match on.
--
-- Reuses public._pricing_setting_num() from security-11-pricing-settings.sql
-- and public.add_wallet_balance() from security-02-wallet.sql — no new
-- helper functions needed.
-- ═══════════════════════════════════════════════════════════════

insert into public.app_settings (key, value) values ('marketplace_listing_fee', '5')
on conflict (key) do nothing;

create or replace function public.guard_marketplace_item()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_role    text;
  v_fee     numeric;
  v_balance numeric;
begin
  select role into v_role from public.accounts
   where phone in (new.seller_phone,
                   case when new.seller_phone like '+20%' then '0'||substr(new.seller_phone,4) else new.seller_phone end,
                   case when new.seller_phone like '0%'   then '+2'||new.seller_phone           else new.seller_phone end)
   limit 1;

  if v_role = 'merchant' then
    new.seller_type := 'merchant';
    if new.quantity > 500 then new.quantity := 500; end if;
  else
    new.seller_type := 'customer';
    new.quantity := 1; -- الأفراد: قطعة واحدة لكل إعلان (لا يُستخدم كمتجر مصغّر)
  end if;

  new.status := 'active';       -- النشر فوري دائماً (لا يمكن للعميل تعيين حالة مبدئية أخرى)
  new.reports_count := 0;

  -- رسم نشر الإعلان — يُخصم من محفظة البائع؛ لو الرصيد مايكفيش، الإعلان
  -- ماينشرش خالص (بلا خصم جزئي أو دين).
  v_fee := public._pricing_setting_num('marketplace_listing_fee', 5, 0);
  if v_fee > 0 then
    select balance into v_balance from public.wallets where phone = new.seller_phone;
    v_balance := coalesce(v_balance, 0);
    if v_balance < v_fee then
      raise exception 'insufficient_wallet_balance:needs=%:has=%', v_fee, v_balance;
    end if;
    perform public.add_wallet_balance(new.seller_phone, -v_fee);
    insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
    values (
      'wtx-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
      new.seller_phone, -v_fee, 'marketplace_fee', new.id,
      'رسم نشر إعلان في سوق المستعمل', now()
    );
  end if;

  return new;
end;
$$;
