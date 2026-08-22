-- =====================================================================
--  وصّلها — Security #34: صفحة بروفايل كاملة لكل مستخدم في لوحة الإدارة
--
--  admin_list_accounts (security06accountslockdown.sql) بترجع أعمدة
--  accounts الأساسية بس (بدون national_id/national_id_expiry/avatar_url)
--  — كافية لجدول القائمة، مش كافية لصفحة بروفايل كاملة. الدالة دي
--  بترجع نفس صف admin_list_accounts + الأعمدة الإضافية دي لمستخدم واحد
--  فقط (بمطابقة رقم هاتف حصرية)، بنفس حماية كلمة مرور المشرف.
--
--  باقي بيانات البروفايل (رحلات/طلبات/محفظة/تقييمات/متجر/طلب اعتماد
--  سائق أو تاجر) مبنية بالفعل على جداول قابلة للقراءة بمفتاح anon
--  (orders/rides/ratings/stores/wallets/driver_applications/
--  merchant_applications) ومتجمّعة client-side بنفس نمط
--  viewUserStats/viewMerchantStats/openDriverModal/openMerchantModal
--  الموجودين بالفعل في admin.astro — ملهمش داعي لدالة SQL إضافية لهم.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.admin_get_account_detail(
  p_admin_phone text, p_admin_password text, p_target_phone text
) returns table(
  id uuid, phone text, name text, role text, city text,
  email text, username text, status text, created_at timestamptz,
  national_id text, national_id_expiry date, avatar_url text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  -- Table alias + fully-qualified columns here: this function's own
  -- RETURNS TABLE declares a "role" output column, which PL/pgSQL also
  -- exposes as a same-named variable in scope — an unqualified "role" in
  -- the WHERE clause below is ambiguous between the two (Postgres error
  -- 42702) and fails at call time, not at CREATE FUNCTION time.
  select a.* into v_admin from public.accounts a
   where a.role = 'admin'
     and a.phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_password';
  end if;

  return query
    select a.id, a.phone, a.name, a.role, a.city, a.email, a.username, a.status, a.created_at,
           a.national_id, a.national_id_expiry, a.avatar_url
    from public.accounts a
    where a.phone in (p_target_phone,
                      case when p_target_phone like '+20%' then '0'||substr(p_target_phone,4) else p_target_phone end,
                      case when p_target_phone like '0%'   then '+2'||p_target_phone           else p_target_phone end)
    limit 1;
end;
$$;
grant execute on function public.admin_get_account_detail(text, text, text) to anon, authenticated;

-- =====================================================================
--  اختبار (استبدل الأرقام ببيانات مشرف حقيقي ورقم هاتف مستخدم موجود):
--    select * from public.admin_get_account_detail('01102667324','ADMIN_PASSWORD','01010785167');
-- =====================================================================
