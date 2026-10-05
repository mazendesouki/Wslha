-- =====================================================================
--  وصّلها — Security #112: استكمال برنامج الدعوات (مشاركة/دعوة أصدقاء)
--
--  الآلية الأساسية (كود دعوة + مكافأة محفظة للطرفين) كانت موجودة بالفعل
--  (security-69) وشغالة، لكن كانت ناقصة:
--   - قيمة المكافأة (20 جنيه) متسجّلة جامدة جوه كود SQL مرتين بدل ما
--     تكون قابلة للتعديل من app_settings زي كل الإعدادات التانية.
--   - مفيش أي طريقة للعميل يشوف "مين دعوت" ولا "كسبت كام من الدعوات" —
--     RPC واحدة بس بترجّع الكود، مفيش إحصائيات أو سجل.
--   - مفيش أي رؤية للأدمن (عدد الدعوات، إجمالي المكافآت المدفوعة).
--
--  الملف ده يضيف الناقص من غير أي لمسة لمنطق redeem_referral_code
--  الأساسي (نفس شرط عدم التكرار، نفس نمط الاعتماد على wallet_transactions
--  type='referral_credit' كمصدر الحقيقة).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value) values
  ('referral_reward_amount', '20')
on conflict (key) do nothing;

-- redeem_referral_code يقرا المكافأة من app_settings دلوقتي بدل القيمة
-- الجامدة، من غير أي تغيير تاني في المنطق.
create or replace function public.redeem_referral_code(p_phone text, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner_phone text;
  v_already text;
  v_reward numeric;
  v_tx_id text;
begin
  select phone into v_owner_phone from public.accounts where referral_code = upper(trim(p_code)) limit 1;
  if v_owner_phone is null or v_owner_phone = p_phone then
    return false;
  end if;

  select referred_by into v_already from public.accounts where phone = p_phone;
  if v_already is not null then
    return false;
  end if;

  v_reward := public._pricing_setting_num('referral_reward_amount', 20, 0);

  update public.accounts set referred_by = v_owner_phone where phone = p_phone;

  v_tx_id := 'ref-cr-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6);
  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values (v_tx_id, p_phone, v_reward, 'referral_credit', 'مكافأة استخدام كود دعوة', now());
  perform public.add_wallet_balance(p_phone, v_reward);

  v_tx_id := 'ref-cr-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6) || '-o';
  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values (v_tx_id, v_owner_phone, v_reward, 'referral_credit', 'مكافأة دعوة صديق جديد', now());
  perform public.add_wallet_balance(v_owner_phone, v_reward);

  return true;
end;
$$;
grant execute on function public.redeem_referral_code(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- إحصائيات العميل: كام شخص دعا + إجمالي اللي كسبه من الدعوات (الاتنين
-- الاتجاهين: مكافأة استخدام كود حد تاني + مكافآت استخدام الناس لكوده).
-- ---------------------------------------------------------------------
create or replace function public.get_my_referral_stats(p_phone text)
returns table(referred_count int, total_earned numeric)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    (select count(*)::int from public.accounts where referred_by = p_phone),
    (select coalesce(sum(amount), 0) from public.wallet_transactions where phone = p_phone and type = 'referral_credit');
$$;
grant execute on function public.get_my_referral_stats(text) to anon, authenticated;

-- قائمة "مين دعوت" — اسم وتاريخ الانضمام بس (من غير رقم هاتف كامل،
-- نفس نهج get_public_app_reviews في إخفاء بيانات الاتصال).
create or replace function public.list_my_referrals(p_phone text, p_limit int default 50)
returns table(name text, created_at timestamptz)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select name, created_at from public.accounts
  where referred_by = p_phone
  order by created_at desc
  limit greatest(coalesce(p_limit, 50), 1);
$$;
grant execute on function public.list_my_referrals(text, int) to anon, authenticated;

-- ---------------------------------------------------------------------
-- نظرة الأدمن: إجمالي عدد الدعوات الناجحة + إجمالي المكافآت المدفوعة.
-- ---------------------------------------------------------------------
create or replace function public.admin_get_referral_overview(p_admin_phone text, p_admin_password text)
returns table(total_referred int, total_rewards_paid numeric, reward_amount numeric)
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
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return;
  end if;

  return query
  select
    (select count(*)::int from public.accounts where referred_by is not null),
    (select coalesce(sum(amount), 0) from public.wallet_transactions where type = 'referral_credit'),
    public._pricing_setting_num('referral_reward_amount', 20, 0);
end;
$$;
grant execute on function public.admin_get_referral_overview(text, text) to anon, authenticated;
