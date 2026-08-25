-- =====================================================================
--  وصّلها — Security #35: نظام تفاوض السعر على المشاوير (اختياري)
--
--  إضافة اختيارية جنب الحجز العادي بسعر ثابت (guard_ride_fare) —
--  العميل يقدر يختار "اطلب بسعر تفاوضي" بدل السعر الثابت، فيشوف عروض
--  أسعار من أكتر من سائق ويختار اللي يناسبه، بدل ما ياخد أول سائق
--  يقبل بالسعر المحسوب تلقائيًا.
--
--  guard_ride_fare() (security-11) يشتغل BEFORE INSERT بس، مش UPDATE —
--  يعني السعر النهائي اللي بنكتبه هنا وقت القبول (fare = السعر المتفق
--  عليه) مش هيتلغى أو يتكتب فوقه، من غير أي تعديل على الدالة دي.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) علم "رحلة تفاوضية" على rides + جدول عروض الأسعار
-- ---------------------------------------------------------------------
alter table public.rides add column if not exists is_negotiable boolean not null default false;

create table if not exists public.ride_price_offers (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null,
  driver_phone text not null,
  driver_name text,
  offered_price numeric not null check (offered_price > 0),
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  unique (ride_id, driver_phone)
);
create index if not exists ride_price_offers_ride_idx on public.ride_price_offers (ride_id);
create index if not exists ride_price_offers_driver_idx on public.ride_price_offers (driver_phone);

-- القراءة مفتوحة (العميل بيتابع العروض على رحلته لحظيًا، والسائق بيشوف
-- عروضه الخاصة) — الكتابة كلها عن طريق الدالتين تحت بس، بنفس نمط
-- إغلاق rides/orders المباشر المطبّق في أمانات سابقة.
alter table public.ride_price_offers enable row level security;
drop policy if exists ride_price_offers_select_all on public.ride_price_offers;
create policy ride_price_offers_select_all on public.ride_price_offers for select to anon, authenticated using (true);
revoke insert, update, delete on public.ride_price_offers from anon, authenticated;
grant select on public.ride_price_offers to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) submit_ride_price_offer — سائق بيقدّم أو يعدّل عرض سعره على رحلة
--    تفاوضية لسه مفتوحة (مفيش سائق اتقبل عليها).
-- ---------------------------------------------------------------------
create or replace function public.submit_ride_price_offer(
  p_ride_id uuid, p_driver_phone text, p_driver_name text, p_price numeric
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_ride record; v_row record;
begin
  if p_price is null or p_price <= 0 then
    raise exception 'invalid_price';
  end if;

  select * into v_ride from public.rides where id = p_ride_id;
  if v_ride.id is null then raise exception 'ride_not_found'; end if;
  if not coalesce(v_ride.is_negotiable, false) then raise exception 'not_negotiable'; end if;
  if v_ride.status <> 'pending' or v_ride.driver_phone is not null then
    raise exception 'ride_already_taken';
  end if;

  insert into public.ride_price_offers (ride_id, driver_phone, driver_name, offered_price)
  values (p_ride_id, p_driver_phone, p_driver_name, p_price)
  on conflict (ride_id, driver_phone)
  do update set offered_price = excluded.offered_price,
                driver_name   = excluded.driver_name,
                status        = 'pending',
                created_at    = now()
  returning to_jsonb(ride_price_offers.*) into v_row;

  return to_jsonb(v_row);
end;
$$;
grant execute on function public.submit_ride_price_offer(uuid, text, text, numeric) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) accept_ride_price_offer — العميل بيختار عرض سعر معيّن، وده اللي
--    بيقفل الرحلة على السائق ده بنفس سعره (fare = السعر المتفق عليه)،
--    بنفس حارس التزامن (WHERE driver_phone IS NULL) المستخدم في
--    accept_dispatch_offer عشان مايتقبلش عرضين على نفس الرحلة.
-- ---------------------------------------------------------------------
create or replace function public.accept_ride_price_offer(
  p_ride_id uuid, p_offer_id uuid, p_customer_phone text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_ride record; v_offer record; v_updated record;
begin
  select * into v_ride from public.rides where id = p_ride_id;
  if v_ride.id is null then raise exception 'ride_not_found'; end if;

  if v_ride.customer_phone not in (
       p_customer_phone,
       case when p_customer_phone like '+20%' then '0'||substr(p_customer_phone,4) else p_customer_phone end,
       case when p_customer_phone like '0%'   then '+2'||p_customer_phone           else p_customer_phone end
     ) then
    raise exception 'not_your_ride';
  end if;

  select * into v_offer from public.ride_price_offers where id = p_offer_id and ride_id = p_ride_id;
  if v_offer.id is null then raise exception 'offer_not_found'; end if;
  if v_offer.status <> 'pending' then raise exception 'offer_no_longer_available'; end if;

  update public.rides
     set status = 'accepted',
         driver_phone = v_offer.driver_phone,
         driver_name  = coalesce(v_offer.driver_name, driver_name),
         fare = v_offer.offered_price,
         accepted_at = now()
   where id = p_ride_id and driver_phone is null
   returning to_jsonb(rides.*) into v_updated;

  if v_updated is null then
    raise exception 'ride_already_taken';
  end if;

  update public.ride_price_offers set status = 'accepted' where id = p_offer_id;
  update public.ride_price_offers set status = 'rejected'
   where ride_id = p_ride_id and id <> p_offer_id and status = 'pending';

  return v_updated;
end;
$$;
grant execute on function public.accept_ride_price_offer(uuid, uuid, text) to anon, authenticated;

-- =====================================================================
--  ملاحظة: تصفّح السائقين لطلبات التفاوض القريبة بيتم عن طريق قراءة
--  rides مباشرة (is_negotiable=true, status=pending, driver_phone is
--  null) — الجدول ده أصلاً مقروء بمفتاح anon (security07rlslockdown.sql)
--  فمحتجناش دالة جديدة للتصفح، بس للكتابة (تقديم عرض / قبول عرض).
-- =====================================================================
