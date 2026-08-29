-- =====================================================================
--  وصّلها — Security #49: قفل قراءة wallets الجماعية + عناوين العملاء المحفوظة
--
--  آخر نقطتين من نفس المراجعة الأمنية الموسّعة:
--
--   1) wallets: كانت SELECT مفتوحة بـ using(true) بلا أي فلتر — أي حد
--      معاه الـ anon key يقدر يعمل GET /rest/v1/wallets?select=* ويشوف
--      رصيد كل مستخدم في المنصة دفعة واحدة. الحل: قفل القراءة المباشرة
--      واستبدالها بدالة get_my_wallet_balance(phone) — بترجع رصيد رقم
--      واحد بس في كل مرة (مش كل الأرصدة سوا)، بنفس مستوى الثقة اللي
--      باقي الجدول بيشتغل بيه فعلاً (رقم الهاتف = الهوية، من غير
--      Supabase Auth حقيقي — زي orders/rides/driver_applications).
--
--   2) saved_addresses: كانت مفتوحة بالكامل (SELECT/UPDATE/DELETE كلهم
--      using(true) من غير أي فلتر خالص، مش حتى فلتر بسيط) — يعني GET
--      /rest/v1/saved_addresses?select=* كان بيرجّع عناوين كل العملاء
--      كلهم مرة واحدة، وأي id (حتى لو اتعرف بالصدفة) كان قابل للتعديل/
--      الحذف من أي حد. الحل: دوال بترجع/تعدّل بس عناوين رقم هاتف محدد
--      اتبعت صراحة، وبتتأكد إن العنوان فعلاً بتاع نفس الرقم قبل التعديل/
--      الحذف.
--
--  ملاحظة صريحة: الاتنين دول (زي كل الجدول في المشروع ده) بيعتمدوا على
--  "رقم الهاتف = الهوية" بس، من غير باسورد أو جلسة تسجيل دخول حقيقية —
--  فده بيقفل التفريغ الجماعي (dump كل البيانات مرة واحدة) والتعديل/الحذف
--  العشوائي، لكن مايمنعش حد عارف رقم هاتف شخص معيّن من قراءة رصيده أو
--  عناوينه المحفوظة تحديدًا. إغلاق كامل لده محتاج نظام تسجيل دخول حقيقي
--  (Supabase Auth أو جلسات فعلية) — تغيير معماري أكبر من تعديل سريع.
--
--  ملاحظة: لازم تحدّث الكود بعد تشغيل الملف ده (wallet.astro +
--  driver-dashboard.astro + merchant-dashboard.astro + admin.astro +
--  flutter wallet_repository.dart + account_repository.dart) — موجود في
--  نفس الكوميت.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) get_my_wallet_balance — بديل محكوم لقراءة wallets المباشرة.
-- ---------------------------------------------------------------------
create or replace function public.get_my_wallet_balance(p_phone text)
returns numeric
language sql
security definer
set search_path = public, extensions
as $$
  select coalesce(balance, 0) from public.wallets
   where phone in (p_phone,
                   case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end,
                   case when p_phone like '0%'   then '+2'||p_phone           else p_phone end)
   limit 1;
$$;

grant execute on function public.get_my_wallet_balance(text) to anon, authenticated;

-- Admin panel's "Wallets" tab needs the full list sorted by balance —
-- password-gated like admin_list_accounts, since it's a bulk PII read.
create or replace function public.admin_list_wallets(p_admin_phone text, p_admin_password text)
returns table(phone text, balance numeric, updated_at timestamptz)
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

  return query
    select w.phone, w.balance, w.updated_at from public.wallets w
     order by w.balance desc limit 2000;
end;
$$;
grant execute on function public.admin_list_wallets(text, text) to anon, authenticated;

revoke select on public.wallets from anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) عناوين العملاء المحفوظة — دوال بدل الوصول المباشر للجدول.
-- ---------------------------------------------------------------------
create or replace function public.list_saved_addresses(p_phone text)
returns setof public.saved_addresses
language sql
security definer
set search_path = public, extensions
as $$
  select * from public.saved_addresses
   where customer_phone = p_phone
   order by is_default desc, created_at desc;
$$;
grant execute on function public.list_saved_addresses(text) to anon, authenticated;

create or replace function public.add_saved_address(
  p_phone text, p_label text, p_area text, p_address text, p_make_default boolean default false
) returns public.saved_addresses
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_row public.saved_addresses;
begin
  if p_make_default then
    update public.saved_addresses set is_default = false where customer_phone = p_phone;
  end if;
  insert into public.saved_addresses (customer_phone, label, area, address, is_default)
  values (p_phone, coalesce(nullif(trim(p_label), ''), 'المنزل'), p_area, p_address, p_make_default)
  returning * into v_row;
  return v_row;
end;
$$;
grant execute on function public.add_saved_address(text, text, text, text, boolean) to anon, authenticated;

create or replace function public.update_saved_address(
  p_id uuid, p_phone text, p_label text, p_area text, p_address text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  update public.saved_addresses
     set label = coalesce(nullif(trim(p_label), ''), label), area = p_area, address = p_address
   where id = p_id and customer_phone = p_phone;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.update_saved_address(uuid, text, text, text, text) to anon, authenticated;

create or replace function public.set_default_saved_address(p_id uuid, p_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  update public.saved_addresses set is_default = false where customer_phone = p_phone;
  update public.saved_addresses set is_default = true where id = p_id and customer_phone = p_phone;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.set_default_saved_address(uuid, text) to anon, authenticated;

create or replace function public.delete_saved_address(p_id uuid, p_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  delete from public.saved_addresses where id = p_id and customer_phone = p_phone;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.delete_saved_address(uuid, text) to anon, authenticated;

drop policy if exists saved_addresses_select on public.saved_addresses;
drop policy if exists saved_addresses_insert on public.saved_addresses;
drop policy if exists saved_addresses_update on public.saved_addresses;
drop policy if exists saved_addresses_delete on public.saved_addresses;
revoke select, insert, update, delete on public.saved_addresses from anon, authenticated;

-- =====================================================================
--  Done.
-- =====================================================================
