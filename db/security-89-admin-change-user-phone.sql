-- =====================================================================
--  وصّلها — Security #89: تغيير رقم موبايل مستخدم من لوحة التحكم
--
--  السيناريو: مستخدم عايز يغيّر رقم موبايله بيتواصل مع الدعم الفني،
--  والأدمن هو اللي بيغيّره من اللوحة — مش المستخدم بنفسه من التطبيق.
--
--  المشكلة المعمارية: المشروع ده بيستخدم رقم الموبايل كـ"مفتاح هوية"
--  فعلي في أكتر من 30 عمود عبر الجداول كلها (rides.customer_phone،
--  orders.driver_phone، wallet_transactions.phone، ratings...، إلخ) —
--  مش عمود عادي بيتغيّر في مكان واحد. لو غيّرنا accounts.phone بس،
--  كل سجل قديم (رحلات، محفظة، تقييمات، عناوين محفوظة...) هيتقطع من
--  صاحبه فعليًا (orphaned) لأنه لسه شايل الرقم القديم.
--
--  الحل: admin_change_user_phone() بتعمل sweep على كل عمود في الـ schema
--  اسمه فيه "phone" (عن طريق information_schema — أوتوماتيك، مش قائمة
--  يدوية ممكن ننسى نحدّثها لو اتضاف عمود جديد بعدين) وتحدّث كل نسخة من
--  الرقم القديم (شكل محلي 0... أو دولي +20...) للرقم الجديد بنفس الشكل.
--
--  5 أعمدة منها عليها foreign key حقيقي على accounts(phone)
--  (wallets/wallet_transactions/points/point_transactions/
--  push_subscriptions) — كانت بدون DEFERRABLE، يعني أي تحديث لـ
--  accounts.phone كان هيفشل فورًا (القيد بيتفحص لحظيًا، مش في نهاية
--  الـ transaction) لأن الصفوف التابعة لسه شايلة القيمة القديمة. حوّلنا
--  القيود دي لـ DEFERRABLE INITIALLY DEFERRED عشان يتفحصوا في نهاية
--  الـ transaction بعد ما كل الجداول (الأب والأبناء) بقوا متحدّثين
--  بالقيمة الجديدة، بدل ما يتفحصوا سطر بسطر.
--
--  بعد التغيير: accounts.auth_user_id بيترجع NULL (لو كان مربوط بهوية
--  Supabase Auth قديمة عبر OTP — security-88) عشان أول OTP جديد على
--  الرقم الجديد يربط الحساب تلقائيًا من غير تعارض.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.wallets alter constraint wallets_phone_fkey deferrable initially deferred;
alter table public.wallet_transactions alter constraint wallet_transactions_phone_fkey deferrable initially deferred;
alter table public.points alter constraint points_phone_fkey deferrable initially deferred;
alter table public.point_transactions alter constraint point_transactions_phone_fkey deferrable initially deferred;
alter table public.push_subscriptions alter constraint push_subscriptions_phone_fkey deferrable initially deferred;

create or replace function public.admin_change_user_phone(
  p_admin_phone text, p_admin_password text, p_target_phone text, p_new_phone text, p_action_key text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin record;
  v_old_local text; v_old_intl text;
  v_new_local text; v_new_intl text;
  v_target record;
  v_col record;
begin
  -- Same sensitive-action key every other identity-altering admin RPC
  -- requires (admin_delete_account, grant_admin, ...) — a phone swap
  -- touches every table this user's history lives in, same blast radius
  -- as a full account delete.
  if not public.verify_action_key(p_action_key) then return false; end if;

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

  v_old_local := case when p_target_phone like '+20%' then '0'||substr(p_target_phone,4) else p_target_phone end;
  v_old_intl  := case when v_old_local like '0%' then '+2'||v_old_local else v_old_local end;

  v_new_local := case when p_new_phone like '+20%' then '0'||substr(p_new_phone,4) else p_new_phone end;
  v_new_intl  := case when v_new_local like '0%' then '+2'||v_new_local else v_new_local end;

  if v_new_local !~ '^01[0125][0-9]{8}$' then
    raise exception 'invalid_new_phone';
  end if;

  select * into v_target from public.accounts where phone in (v_old_local, v_old_intl) limit 1;
  if v_target.phone is null then raise exception 'account_not_found'; end if;

  if exists (select 1 from public.accounts where phone in (v_new_local, v_new_intl) and phone <> v_target.phone) then
    raise exception 'new_phone_already_used';
  end if;

  update public.accounts set phone = v_new_local, auth_user_id = null where phone = v_target.phone;

  for v_col in
    select table_name, column_name from information_schema.columns
     where table_schema = 'public' and column_name ilike '%phone%'
       and table_name <> 'accounts'
  loop
    execute format('update public.%I set %I = $1 where %I = $2', v_col.table_name, v_col.column_name, v_col.column_name)
      using v_new_local, v_old_local;
    execute format('update public.%I set %I = $1 where %I = $2', v_col.table_name, v_col.column_name, v_col.column_name)
      using v_new_intl, v_old_intl;
  end loop;

  return true;
end;
$$;
grant execute on function public.admin_change_user_phone(text, text, text, text, text) to anon, authenticated;
