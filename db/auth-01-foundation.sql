-- =====================================================================
--  وصّلها — Auth Migration · المرحلة 1: الأساس (آمن وإضافي)
--
--  لا يكسر شيئاً. النظام القديم يبقى يعمل بالتوازي.
--  شغّله بعد إعداد مزوّد SMS (المرحلة 0).
-- =====================================================================

-- 1) عمود ربط حساب التطبيق بمستخدم Supabase Auth (يُملأ عند أول دخول OTP)
alter table public.accounts
  add column if not exists auth_user_id uuid unique;

-- 2) دالة مساعدة: هل المستخدم الحالي أدمن؟ (تُستخدم لاحقاً في سياسات RLS)
--    تعتمد على ربط auth.uid() بصف accounts ذي الدور admin.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.accounts
    where auth_user_id = auth.uid() and role = 'admin'
  );
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- 3) عند إنشاء مستخدم Auth جديد (أول دخول OTP): اربط/أنشئ صف accounts.
--    الهاتف يأتي في auth.users.phone (بصيغة دولية بدون +، مثل 201xxxxxxxxx).
create or replace function public.link_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_local text;
  v_intl  text;
begin
  if new.phone is null or length(new.phone) = 0 then
    return new;
  end if;
  -- صيغ الهاتف المحتملة في accounts
  v_intl  := '+' || new.phone;                 -- +20100...
  v_local := '0' || right(new.phone, 10);       -- 0100...

  -- اربط أقدم صف مطابق إن وُجد، وإلا أنشئ صفاً جديداً بدور عميل
  update public.accounts
     set auth_user_id = new.id
   where auth_user_id is null
     and (phone = v_intl or phone = v_local)
     and ctid = (
       select ctid from public.accounts
        where phone = v_intl or phone = v_local
        order by created_at nulls last limit 1
     );

  if not found then
    insert into public.accounts (phone, name, role, status, created_at, auth_user_id)
    values (v_local, 'مستخدم', 'customer', 'active', now(), new.id)
    on conflict (phone) do update set auth_user_id = excluded.auth_user_id;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.link_auth_user();

-- =====================================================================
--  بعد هذا: المرحلة 2 (تسجيل الدخول عبر signInWithOtp/verifyOtp).
--  لا تُفعّل أي RLS جديد هنا — يبقى كل شيء كما هو حتى تكتمل المرحلة 3.
-- =====================================================================
