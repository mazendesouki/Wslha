-- =====================================================================
--  وصّلها — Security #111: مراجعات/شهادات عامة للتطبيق
--
--  مختلف عن جدول ratings الموجود (security-45) — ده مربوط دايمًا برحلة/
--  طلب فعلي (ride_id/order_code) وبيتقيّم بيه السائق/المتجر بعد كل
--  خدمة. المطلوب هنا حاجة تانية: مراجعة عامة عن التطبيق نفسه (زي تقييم
--  على App Store) تتعرض كـ "شهادات" في الصفحة الرئيسية للموقع لبناء
--  ثقة عند زوار جدد — مش مربوطة برحلة معيّنة، وبتحتاج موافقة أدمن الأول
--  قبل ما تظهر للعامة (منعًا للسبام/الإساءة).
--
--  الجدول مقفول بالكامل (زي points/وcoupons) — قراءة/كتابة بس عن طريق
--  دوال:
--   - submit_app_review(phone, name, rating, comment) — العميل يقدر
--     يبعت/يعدّل مراجعته (upsert بالـ phone، مراجعة واحدة لكل عميل)،
--     بترجع is_approved=false لحد ما الأدمن يوافق عليها.
--   - get_public_app_reviews(limit) — قراءة عامة (anon) للمراجعات
--     الموافق عليها بس، تُستخدم في index.astro.
--   - admin_list_app_reviews / admin_set_app_review_approved — إدارة
--     وموافقة الأدمن (نفس نمط admin_* الباسورد المعتاد).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.app_reviews (
  id uuid primary key default gen_random_uuid(),
  customer_phone text not null unique,
  customer_name text not null,
  rating int not null check (rating between 1 and 5),
  comment text,
  is_approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.app_reviews enable row level security;
revoke all on public.app_reviews from anon, authenticated;

-- ---------------------------------------------------------------------
-- العميل يبعت/يعدّل مراجعته — مراجعة واحدة بس لكل رقم هاتف (upsert)،
-- وأي تعديل بيرجّعها "غير موافق عليها" تاني لحد ما الأدمن يراجعها.
-- ---------------------------------------------------------------------
create or replace function public.submit_app_review(
  p_phone text, p_name text, p_rating int, p_comment text
) returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_id uuid;
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'invalid_rating';
  end if;

  insert into public.app_reviews (customer_phone, customer_name, rating, comment, is_approved, updated_at)
  values (p_phone, coalesce(nullif(trim(p_name), ''), 'عميل وصّلها'), p_rating, p_comment, false, now())
  on conflict (customer_phone)
  do update set customer_name = excluded.customer_name,
                rating = excluded.rating,
                comment = excluded.comment,
                is_approved = false,
                updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.submit_app_review(text, text, int, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- قراءة عامة (الموقع) — المراجعات الموافق عليها بس، بدون رقم الهاتف.
-- ---------------------------------------------------------------------
create or replace function public.get_public_app_reviews(p_limit int default 6)
returns table(customer_name text, rating int, comment text, created_at timestamptz)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select customer_name, rating, comment, created_at
  from public.app_reviews
  where is_approved = true
  order by created_at desc
  limit greatest(coalesce(p_limit, 6), 1);
$$;
grant execute on function public.get_public_app_reviews(int) to anon, authenticated;

-- ---------------------------------------------------------------------
-- إدارة الأدمن — عرض الكل (معلّق + موافق عليه) والموافقة/الرفض.
-- ---------------------------------------------------------------------
create or replace function public.admin_list_app_reviews(p_admin_phone text, p_admin_password text, p_limit int default 100)
returns setof public.app_reviews
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
  return query select * from public.app_reviews order by is_approved asc, created_at desc limit p_limit;
end;
$$;
grant execute on function public.admin_list_app_reviews(text, text, int) to anon, authenticated;

create or replace function public.admin_set_app_review_approved(
  p_admin_phone text, p_admin_password text, p_review_id uuid, p_approved boolean
) returns boolean
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
  if v_admin.phone is null then return false; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;

  update public.app_reviews set is_approved = p_approved, updated_at = now() where id = p_review_id;
  return found;
end;
$$;
grant execute on function public.admin_set_app_review_approved(text, text, uuid, boolean) to anon, authenticated;
