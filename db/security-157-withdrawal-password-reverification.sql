-- =====================================================================
--  وصّلها — Security #157: تأكيد كلمة المرور قبل سحب الرصيد (Phase 0 من
--  خطة تصحيح IDOR)
--
--  اتكشف وقت تحليل قائمة فحص الأمان قبل الإطلاق: request_withdrawal
--  كانت بتخصم الرصيد فعليًا وتسجّل طلب سحب بالاعتماد الكامل على
--  p_phone اللي العميل بيبعته — من غير أي إثبات إن اللي بيتصل هو فعلاً
--  صاحب الرقم ده. أي حد معاه الـ anon key العام (مكشوف في كل تطبيق) +
--  رقم تليفون أي مستخدم، يقدر يسحب رصيده لوجهة هو اختارها. ده مش خطر
--  مستقبلي — ده ثغرة فعلية بتحرّك فلوس حقيقية دلوقتي.
--
--  الحل (الأولوية الفورية من خطة تصحيح IDOR الأشمل — باقي الخطة أكبر
--  وبتحتاج نظام الـ session الموجود فعلاً في src/lib/session.ts يتمد
--  لتطبيقات الفلاتر، ده شغل منفصل وأكبر): إضافة باراميتر p_password
--  إجباري لـ request_withdrawal، بيتفحص بنفس طريقة wallet_transfer
--  (bcrypt عن طريق extensions.crypt). التوقيع بيتغيّر (باراميتر جديد
--  إجباري) فده محتاج rename-deprecated مش CREATE OR REPLACE عادي، عشان
--  منتجناش overload غامض.
--
--  كمان لقينا نفس باگ security-156 بالظبط (مقارنة كلمة مرور احتياطية
--  بنص صريح) موجود في wallet_transfer من الأول — نفس المنطق: 0 من 9
--  حسابات لسه بكلمة مرور مش bcrypt، فالمقارنة الاحتياطية دي مخاطرة
--  دايمة من غير فايدة. اتشالت هنا كمان (نفس التوقيع، CREATE OR REPLACE
--  آمن).
--
--  آمن لإعادة التشغيل — عدا سطر الـ rename اللي بيتجاهل الخطأ لو
--  الدالة القديمة متسماش قبل كده (DO block).
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) request_withdrawal — rename-deprecate التوقيع القديم (بدون باسورد).
-- ---------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'request_withdrawal'
      and pg_get_function_identity_arguments(p.oid) = 'p_phone text, p_amount numeric, p_dest text, p_note text'
  ) then
    alter function public.request_withdrawal(text, numeric, text, text) rename to request_withdrawal_deprecated_v1;
    revoke all on function public.request_withdrawal_deprecated_v1(text, numeric, text, text) from public, anon, authenticated;
  end if;
end $$;

create or replace function public.request_withdrawal(
  p_phone text, p_amount numeric, p_dest text, p_password text, p_note text default null
)
returns public.wallet_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_acct public.accounts%rowtype;
  v_bal numeric;
  v_row public.wallet_requests;
  v_amt numeric := round(p_amount::numeric, 2);
begin
  -- إثبات إن اللي بيتصل هو فعلاً صاحب p_phone — نفس نمط wallet_transfer،
  -- لكن من غير المقارنة الاحتياطية بنص صريح (security-157).
  select * into v_acct from public.accounts where phone = p_phone limit 1;
  if v_acct.phone is null or v_acct.password is null
     or v_acct.password <> extensions.crypt(p_password, v_acct.password) then
    raise exception 'invalid_credentials';
  end if;

  if v_amt is null or v_amt < 10 then raise exception 'amount_too_small'; end if;
  if p_dest is null or length(trim(p_dest)) = 0 then raise exception 'destination_required'; end if;

  select balance into v_bal from public.wallets where phone = p_phone for update;
  if v_bal is null then v_bal := 0; end if;
  if v_amt > v_bal then raise exception 'insufficient_funds'; end if;

  -- reserve the money now so it cannot be spent twice
  update public.wallets set balance = balance - v_amt, updated_at = now() where phone = p_phone;

  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values ('wtx-w-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,5),
          p_phone, -v_amt, 'withdrawal',
          coalesce(nullif(trim(p_note),''),'سحب رصيد') || ' — إلى ' || p_dest, now());

  insert into public.wallet_requests (id, phone, kind, amount, destination, note)
  values ('wd-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,6),
          p_phone, 'withdrawal', v_amt, p_dest, p_note)
  returning * into v_row;

  return v_row;
end;
$$;
grant execute on function public.request_withdrawal(text, numeric, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) wallet_transfer — شيل نفس المقارنة الاحتياطية بنص صريح (نفس
--    التوقيع، CREATE OR REPLACE آمن).
-- ---------------------------------------------------------------------
create or replace function public.wallet_transfer(
  p_from text, p_from_password text, p_to text, p_amount numeric, p_note text default null
)
returns numeric
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_from_acct record;
  v_from_bal numeric;
  v_to_exists boolean;
  v_amt numeric := round(p_amount::numeric, 2);
  v_note text := coalesce(nullif(trim(p_note),''),'تحويل');
begin
  if v_amt is null or v_amt < 1 then raise exception 'amount_too_small'; end if;
  if p_from = p_to then raise exception 'same_account'; end if;

  select * into v_from_acct from public.accounts where phone = p_from limit 1;
  if v_from_acct.phone is null
     or v_from_acct.password is null
     or v_from_acct.password <> extensions.crypt(p_from_password, v_from_acct.password) then
    raise exception 'invalid_credentials';
  end if;

  select exists(select 1 from public.accounts where phone = p_to) into v_to_exists;
  if not v_to_exists then raise exception 'recipient_not_found'; end if;

  select balance into v_from_bal from public.wallets where phone = p_from for update;
  if v_from_bal is null then v_from_bal := 0; end if;
  if v_amt > v_from_bal then raise exception 'insufficient_funds'; end if;

  update public.wallets set balance = balance - v_amt, updated_at = now() where phone = p_from;

  insert into public.wallets (phone, balance, updated_at)
  values (p_to, v_amt, now())
  on conflict (phone) do update set balance = public.wallets.balance + excluded.balance, updated_at = now();

  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values ('wtx-out-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,5),
          p_from, -v_amt, 'transfer_out', v_note || ' → ' || p_to, now());
  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values ('wtx-in-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,5),
          p_to, v_amt, 'transfer_in', v_note || ' ← ' || p_from, now());

  return v_from_bal - v_amt;
end;
$$;
grant execute on function public.wallet_transfer(text, text, text, numeric, text) to anon, authenticated;
