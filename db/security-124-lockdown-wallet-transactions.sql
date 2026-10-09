-- =====================================================================
--  وصّلها — Security #124: قفل wallet_transactions
--
--  من مراجعة أمنية شاملة: wallet_transactions كان عليه GRANT SELECT
--  مباشر لـ anon/authenticated (وكمان TRUNCATE/REFERENCES/TRIGGER —
--  منح Supabase الافتراضي عند إنشاء المشروع، مش مستغل فعليًا عن طريق
--  PostgREST لأنها بتعرض REST/RPC بس مش DDL خام، لكن اتقفلت هنا كمان
--  لتقليل أي سطح هجوم لأي اتصال Postgres مباشر لاحقًا). النتيجة:
--  GET /rest/v1/wallet_transactions?select=* كان بيرجع سجل المعاملات
--  المالية الكامل لكل مستخدم في المنصة — بدون أي فلتر.
--
--  wallets (الرصيد نفسه) كانت محصّنة بالفعل من قبل (security-02/49)؛
--  wallet_transactions (السجل التاريخي) فاتت في وقتها.
--
--  الإصلاح: revoke all + دوال محصورة بديلة (العميل نفسه، أو الأدمن
--  بالباسورد زي باقي دوال الأدمن).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

revoke all on public.wallet_transactions from anon, authenticated;

create or replace function public.get_my_wallet_transactions(p_phone text, p_limit int default 50)
returns setof public.wallet_transactions
language sql
security definer
set search_path = public, extensions
as $$
  select * from public.wallet_transactions
   where phone = p_phone
   order by created_at desc
   limit greatest(1, least(p_limit, 500));
$$;
grant execute on function public.get_my_wallet_transactions(text, int) to anon, authenticated;

-- سجل غرامات رحلة معيّنة (متأخّر سائق/عميل) — محصور بمرجع الرحلة نفسها،
-- مش برقم تليفون، زي ما كان الاستخدام الأصلي في فاتورة الرحلة
-- (ride_repository.dart's fetchRidePenalties).
create or replace function public.get_ride_penalties(p_ride_id text)
returns table(phone text, amount numeric, note text)
language sql
security definer
set search_path = public, extensions
as $$
  select phone, amount, note from public.wallet_transactions
   where reference_id = p_ride_id and type = 'penalty';
$$;
grant execute on function public.get_ride_penalties(text) to anon, authenticated;

create or replace function public.admin_list_wallet_transactions(
  p_admin_phone text, p_admin_password text, p_phone text default null, p_limit int default 500
) returns setof public.wallet_transactions
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return;
  end if;

  if p_phone is not null then
    return query select * from public.wallet_transactions
      where phone = p_phone order by created_at desc limit greatest(1, least(p_limit, 2000));
  else
    return query select * from public.wallet_transactions
      order by created_at desc limit greatest(1, least(p_limit, 2000));
  end if;
end;
$$;
grant execute on function public.admin_list_wallet_transactions(text, text, text, int) to anon, authenticated;
