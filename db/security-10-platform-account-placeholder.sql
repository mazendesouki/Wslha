-- Fixes: insert or update on table "wallet_transactions" violates foreign
-- key constraint "wallet_transactions_phone_fkey" — Key (phone)=(platform)
-- is not present in table "accounts".
--
-- platformnetprofit.sql has always used phone='platform' as a sentinel
-- "account" to book the platform's own commission cut in wallet_transactions
-- (see get_platform_finance_summary / admin_withdraw_platform_profit), but
-- a foreign key added later (accounts lockdown) never accounted for it, so
-- every commission-settlement insert has been failing. This just creates
-- that placeholder row once — it's never used for login (no valid phone
-- format, no OTP flow will ever match it).

insert into public.accounts (phone, password, name, role, status)
values (
  'platform',
  'no-login-' || substr(md5(random()::text), 1, 24),
  'المنصة — وصّلها',
  'platform',
  'active'
)
on conflict (phone) do nothing;
