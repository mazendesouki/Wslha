-- =====================================================================
--  وصّلها — Security #184: لوحة شكاوى مخصّصة للأدمن
--
--  السؤال اللي أدى للميجريشن ده: هل فيه قسم مخصّص في لوحة التحكم لعرض
--  والرد على رسائل الشكاوى؟ — الإجابة كانت لأ: فيه قسم "الدعم الفني"
--  عام بس (support_conversations، security-73)، وعمود reports_count
--  منفصل للإعلانات في السوق المستعمل بس — مفيش أي حاجة بتجمع الشكاوى
--  الحقيقية (تقييم منخفض + تعليق مكتوب على رحلة/طلب) في مكان واحد
--  قابل للمراجعة والـ follow-up.
--
--  اكتشاف أمني عرضي أثناء بناء الميزة دي: جدول ratings لسه عليه سياسة
--  RLS قديمة "anon all ratings" (FOR ALL USING true WITH CHECK true) +
--  GRANT مباشر لـ UPDATE/DELETE لـ anon/authenticated — يعني أي حد يقدر
--  يمسح أو يعدّل أي تقييم/تعليق لأي حد تاني مباشرة عن طريق PostgREST،
--  بالظبط نفس ثغرة security-26/security-110. REVOKE هنا كفاية يقفلها
--  فعليًا حتى مع بقاء السياسة القديمة (GRANT بيتفحص قبل أي policy).
--
--  الحل:
--   1) قفل الكتابة على ratings تمامًا لـ anon/authenticated (القراءة
--      فضلت مفتوحة عمدًا — التقييمات معروضة أصلاً كـ trust badge على كل
--      سائق). الكتابة التطبيقية التلاتة (submit_ride_rating/
--      submit_customer_rating/submit_order_rating) كلها SECURITY
--      DEFINER فمش هتتأثر.
--   2) أعمدة جديدة على ratings لتتبع حالة الشكوى: complaint_resolved +
--      متى + مين من الأدمن + ملاحظة داخلية (مش ظاهرة للعميل أو السائق).
--   3) admin_list_complaints: بيرجع التقييمات اللي فيها تعليق مكتوب
--      ورقم منخفض (≤3 نجوم) بس — دي الإشارة الوحيدة المتاحة فعليًا على
--      "شكوى حقيقية" (مفيش نظام تذاكر شكاوى منفصل أصلاً)، فلترة بالحالة
--      (مفتوحة/متعاملة معاها).
--   4) admin_resolve_complaint: يسجّل إن الأدمن تعامل مع الشكوى + ملاحظة
--      اختيارية. نفس نمط admin_send_support_reply (تحقق بالتليفون/
--      الباسورد، مش مجرد RLS).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 0) قفل كتابة ratings لـ anon/authenticated
-- ---------------------------------------------------------------------
revoke insert, update, delete, truncate
  on public.ratings
  from anon, authenticated;

-- ---------------------------------------------------------------------
-- 1) أعمدة تتبّع الشكوى
-- ---------------------------------------------------------------------
alter table public.ratings add column if not exists complaint_resolved boolean not null default false;
alter table public.ratings add column if not exists complaint_resolved_at timestamptz;
alter table public.ratings add column if not exists complaint_resolved_by text;
alter table public.ratings add column if not exists admin_note text;

create index if not exists idx_ratings_complaints
  on public.ratings (complaint_resolved, created_at desc)
  where comment is not null and trim(comment) <> '';

-- ---------------------------------------------------------------------
-- 2) admin_list_complaints — تقييمات بتعليق مكتوب + ≤3 نجوم (رحلة أو
--    طلب، سواء على السائق أو المتجر)
-- ---------------------------------------------------------------------
create or replace function public.admin_list_complaints(
  p_admin_phone text, p_admin_password text,
  p_only_open boolean default true, p_limit int default 100
)
returns table (
  id uuid, ride_id text, order_code text, customer_phone text, customer_name text,
  driver_phone text, rating smallint, store_rating int, driver_rating int,
  comment text, driver_reply text, service_type text, created_at timestamptz,
  complaint_resolved boolean, complaint_resolved_at timestamptz,
  complaint_resolved_by text, admin_note text
)
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
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_credentials';
  end if;

  return query
    select r.id, r.ride_id, r.order_code, r.customer_phone, r.customer_name,
           r.driver_phone, r.rating, r.store_rating, r.driver_rating,
           r.comment, r.driver_reply, r.service_type, r.created_at,
           r.complaint_resolved, r.complaint_resolved_at,
           r.complaint_resolved_by, r.admin_note
    from public.ratings r
    where r.comment is not null and trim(r.comment) <> ''
      and (coalesce(r.rating, 5) <= 3 or coalesce(r.store_rating, 5) <= 3 or coalesce(r.driver_rating, 5) <= 3)
      and r.complaint_resolved = (not p_only_open)
    order by r.created_at desc
    limit greatest(p_limit, 1);
end;
$$;
grant execute on function public.admin_list_complaints(text, text, boolean, int) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) admin_resolve_complaint
-- ---------------------------------------------------------------------
create or replace function public.admin_resolve_complaint(
  p_admin_phone text, p_admin_password text,
  p_rating_id uuid, p_note text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_rows int;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_credentials';
  end if;

  update public.ratings
     set complaint_resolved = true,
         complaint_resolved_at = now(),
         complaint_resolved_by = v_admin.phone,
         admin_note = coalesce(trim(p_note), admin_note)
   where id = p_rating_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.admin_resolve_complaint(text, text, uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) admin_reopen_complaint — تراجع عن "اتحلت" لو اتقفلت غلط
-- ---------------------------------------------------------------------
create or replace function public.admin_reopen_complaint(
  p_admin_phone text, p_admin_password text, p_rating_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_rows int;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_credentials';
  end if;

  update public.ratings
     set complaint_resolved = false, complaint_resolved_at = null, complaint_resolved_by = null
   where id = p_rating_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.admin_reopen_complaint(text, text, uuid) to anon, authenticated;
