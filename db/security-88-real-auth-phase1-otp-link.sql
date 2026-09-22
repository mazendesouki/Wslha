-- =====================================================================
--  وصّلها — Security #88: المرحلة ١ من نظام التحقق الحقيقي (Supabase Auth
--  + Twilio Verify OTP) — جنب النظام الحالي مش بدل منه، عشان مانكسرش
--  أي حاجة شغالة. راجع الملخص الكامل للخطة في المحادثة (4 مراحل).
--
--  المشكلة الأساسية اللي المرحلة دي بتحل جزء منها: accounts.phone كان
--  بيتقبل من العميل كـ"معطى" عادي في كل RPC، من غير أي تحقق إنه فعلاً
--  صاحب الرقم ده. دلوقتي بعد ما العميل يعمل OTP حقيقي عبر Supabase Auth
--  (Twilio Verify)، الرقم بييجي موثّق تشفيريًا جوه الـ JWT بتاعه
--  (auth.jwt()->>'phone') — مش قيمة بيبعتها هو، فمينفعش يتزوّر.
--
--  accounts.auth_user_id: عمود جديد (nullable) بيربط صف الحساب القديم
--  بهوية Supabase Auth الحقيقية بعد أول تسجيل دخول بـOTP ناجح. الحسابات
--  اللي لسه مسجّلة دخول بالطريقة القديمة (باسورد) هيفضل العمود ده NULL
--  عندها لحد ما تعمل أول تسجيل دخول بـOTP — مفيش أي كسر لحاجة شغالة.
--
--  link_or_create_account(): بتتنادى من تطبيق الفلاتر بعد نجاح التحقق
--  بـOTP مباشرة (المستخدم بقى authenticated فعليًا في السياق ده). بتاخد
--  الرقم الموثّق من الـ JWT نفسه (مش من أي باراميتر يبعته العميل)،
--  تدوّر على صف accounts موجود بنفس الرقم (تربطه)، أو تنشئ واحد جديد
--  لو الرقم مسجّل لأول مرة.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.accounts
  add column if not exists auth_user_id uuid references auth.users(id);

create unique index if not exists accounts_auth_user_id_key
  on public.accounts(auth_user_id) where auth_user_id is not null;

create or replace function public.link_or_create_account(p_name text default null)
returns public.accounts
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_jwt_phone text;
  v_local text;
  v_intl text;
  v_row public.accounts;
begin
  -- auth.jwt()->>'phone' is set by GoTrue itself once Twilio Verify confirms
  -- the code — this is NOT a client-supplied parameter, it can't be forged.
  v_jwt_phone := auth.jwt() ->> 'phone';
  if v_jwt_phone is null or length(v_jwt_phone) = 0 then
    raise exception 'not_authenticated_via_otp';
  end if;

  -- GoTrue stores the phone as bare digits with country code, no '+'
  -- (e.g. "201012345678") — accounts.phone in this app is the local
  -- 0-prefixed form ("01012345678"). Derive both forms the same way
  -- every other RPC in this project already does (dual-format lookup).
  v_intl := '+' || v_jwt_phone;
  if left(v_jwt_phone, 2) = '20' then
    v_local := '0' || substr(v_jwt_phone, 3);
  else
    v_local := v_jwt_phone;
  end if;

  select * into v_row from public.accounts where phone in (v_local, v_intl) limit 1;

  if v_row.phone is not null then
    if v_row.auth_user_id is null then
      update public.accounts set auth_user_id = auth.uid() where phone = v_row.phone returning * into v_row;
    elsif v_row.auth_user_id <> auth.uid() then
      -- Already linked to a different Supabase Auth identity — shouldn't
      -- happen in normal use (one phone, one OTP identity), but never
      -- silently reassign ownership of an existing account.
      raise exception 'phone_linked_to_different_identity';
    end if;
    return v_row;
  end if;

  -- accounts.password is NOT NULL with no default (every existing row is
  -- the old password-login flow) — an OTP-only account has no password at
  -- all, so a random, never-shared value is inserted here purely to
  -- satisfy the constraint. trg_hash_account_password hashes it same as
  -- any real password; nobody (including this function) ever learns the
  -- plaintext, so it can never actually be used to log in via
  -- verify_login() — this account can only be reached via OTP.
  insert into public.accounts (phone, password, auth_user_id, name, role, created_at)
  values (v_local, encode(extensions.gen_random_bytes(24), 'hex'), auth.uid(), coalesce(nullif(trim(p_name), ''), 'مستخدم جديد'), 'customer', now())
  returning * into v_row;
  return v_row;
end;
$$;
grant execute on function public.link_or_create_account(text) to authenticated;
