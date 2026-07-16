-- =====================================================================
--  وصّلها — حذف الحساب يبقى عملية إدارية موثّقة، مش DELETE مفتوح بمفتاح anon
--
--  admin_delete_account: بديل آمن للحذف اليدوي المباشر — نفس نمط
--  grant_admin/create_admin بالضبط: يتحقق من كلمة مرور مشرف موجود (bcrypt)
--  قبل تنفيذ أي حذف، وينظّف كل الجداول المرتبطة ثم الحساب نفسه في عملية واحدة.
--
--  بعد التشغيل: صلاحية DELETE المباشرة على accounts تُسحب من anon/authenticated
--  تمامًا — الحذف يمر فقط عبر هذه الدالة الموثّقة.
--
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.admin_delete_account(
  p_admin_phone text, p_admin_password text, p_target_phone text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin  record;
  v_local  text;
  v_intl   text;
  v_rows   int;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return false; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;

  v_local := case when p_target_phone like '+20%' then '0'||substr(p_target_phone,4) else p_target_phone end;
  v_intl  := case when p_target_phone like '0%'   then '+2'||p_target_phone           else p_target_phone end;

  -- تنظيف كل الجداول المرتبطة بمفتاح خارجي أو منطقيًا بالتليفون، بالصيغتين
  -- المحلية والدولية (لأن البيانات القديمة قد تكون بأي صيغة).
  delete from public.driver_applications  where phone         in (v_local, v_intl);
  delete from public.merchant_applications where phone        in (v_local, v_intl);
  delete from public.driver_locations     where driver_phone  in (v_local, v_intl);
  delete from public.wallet_transactions  where phone         in (v_local, v_intl);
  delete from public.rides                where driver_phone  in (v_local, v_intl);
  delete from public.rides                where customer_phone in (v_local, v_intl);
  delete from public.orders               where customer_phone in (v_local, v_intl);
  delete from public.points               where phone         in (v_local, v_intl);
  delete from public.point_transactions   where phone         in (v_local, v_intl);
  delete from public.wallets              where phone         in (v_local, v_intl);
  delete from public.push_subscriptions   where phone         in (v_local, v_intl);

  perform set_config('app.privileged', 'on', true);
  delete from public.accounts where phone in (v_local, v_intl);
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);

  return v_rows > 0;
end;
$$;

grant execute on function public.admin_delete_account(text, text, text) to anon, authenticated;

-- الحذف المباشر بمفتاح anon يُقفل تمامًا — فقط عبر الدالة الموثّقة أعلاه.
revoke delete on public.accounts from anon, authenticated;
