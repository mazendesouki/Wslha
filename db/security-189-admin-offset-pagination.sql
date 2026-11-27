-- security-189: offset pagination for admin_list_wallet_transactions
-- آمن لإعادة التشغيل (idempotent) — safe to re-run.
--
-- Companion to the orders/rides pagination added in admin.astro
-- (sbGetPaged/renderPager): this table's admin-wide transaction log was
-- fetched 500-at-a-time with a client-side `.slice(0,200)` display cap —
-- anything past the newest 500 rows (268 today, but growing with every
-- wallet operation) had no way to be reached. Adds p_offset and an
-- optional p_type filter; existing callers that pass neither keep their
-- current behavior exactly (first p_limit rows, newest first).

create index if not exists idx_wallet_transactions_type_created
  on public.wallet_transactions (type, created_at desc);

create or replace function public.admin_list_wallet_transactions(
  p_admin_phone text,
  p_admin_password text,
  p_phone text default null,
  p_limit integer default 500,
  p_offset integer default 0,
  p_type text default null
)
returns setof wallet_transactions
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  return query select * from public.wallet_transactions
    where (p_phone is null or phone = p_phone)
      and (p_type is null or type = p_type)
    order by created_at desc
    limit greatest(1, least(p_limit, 2000))
    offset greatest(0, p_offset);
end;
$function$;
