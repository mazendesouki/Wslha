-- =====================================================================
--  وصّلها — Security #43: حذف ذاتي لحساب سائق لسه "معلّق" (مش معتمد)
--
--  "امنع هذا... ضيف زر بحساب السائق حذف الحساب ليسهل حذف الحساب" —
--  سائق اتحبس في تسجيل ناقص (مثلاً بسبب سيناريو driver.astro اللي
--  اتصلّح في نفس الكوميت ده — دخول برقم موجود بالفعل كان بيوديه لوحة
--  التحكم مباشرة من غير ما يكمّل الوثائق/السيارة) محتاج طريقة يمسح
--  بيها حسابه ويبدأ تسجيل جديد، من غير ما يستنى مراجعة إدارية.
--
--  driver_delete_own_pending_account: بديل ذاتي محدود لـ
--  admin_delete_account (admindeleteaccount.sql) — بيتحقق إن رقم
--  الهاتف بتاع صاحب الطلب نفسه، وبيرفض الحذف لو الحساب already
--  approved/active (عشان محتمل يكون له رحلات/محفظة حقيقية، وده محتاج
--  مراجعة إدارية مش زرار سريع). بينضّف driver_applications +
--  driver_locations + push_subscriptions + الحساب نفسه بس — من غير ما
--  يلمس rides/orders/wallets زي دالة الأدمن، لأن حساب لسه pending
--  المفروض مالوش تاريخ حقيقي أصلاً.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.driver_delete_own_pending_account(p_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_local  text;
  v_intl   text;
  v_acct   record;
  v_app_status text;
  v_rows   int;
begin
  v_local := case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end;
  v_intl  := case when p_phone like '0%'   then '+2'||p_phone          else p_phone end;

  select * into v_acct from public.accounts where phone in (v_local, v_intl) and role = 'driver' limit 1;
  if v_acct.phone is null then return false; end if;

  select status into v_app_status from public.driver_applications
   where phone in (v_local, v_intl) order by created_at desc limit 1;

  -- Only self-deletable while pending (or no application row at all) —
  -- an approved/rejected/reviewed account needs an admin, not a button.
  if v_app_status is not null and v_app_status <> 'pending' then
    return false;
  end if;
  if coalesce(v_acct.status, 'pending') not in ('pending', 'active') then
    return false;
  end if;

  delete from public.driver_applications where phone in (v_local, v_intl);
  delete from public.driver_locations    where driver_phone in (v_local, v_intl);
  delete from public.push_subscriptions  where phone in (v_local, v_intl);

  perform set_config('app.privileged', 'on', true);
  delete from public.accounts where phone in (v_local, v_intl) and role = 'driver';
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);

  return v_rows > 0;
end;
$$;

grant execute on function public.driver_delete_own_pending_account(text) to anon, authenticated;
