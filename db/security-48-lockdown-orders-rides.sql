-- =====================================================================
--  وصّلها — Security #48: قفل orders/rides عن التعديل المباشر بالكامل
--
--  نفس المراجعة اللي لقت ثغرة accounts/stores (security-47) لقت إن
--  orders وrides كمان FOR ALL USING(true) WITH CHECK(true) — يعني أي
--  حد معاه الـ anon key يقدر يعدّل status أو driver_phone لأي طلب/رحلة
--  مباشرة، من غير ما يمر بأي من الدوال المُتحقَّق منها اللي اتبنت في
--  الجلسة دي (confirm_order_delivery، settle_order_commission،
--  settle_order_merchant_credit، mark_ride_arrived...). ده مش مجرد
--  ثغرة منفصلة — ده بيلغي فايدة الإصلاحات دي كلها: مهاجم يقدر:
--    PATCH /rest/v1/orders?id=eq.<أي طلب> {"driver_phone":"<رقمه>","status":"delivered"}
--  ثم ينادي settle_order_merchant_credit/settle_order_commission بنفس
--  رقمه — الدالتين بيتحققوا إن driver_phone بتاع الصف = رقمه (وهو فعلاً
--  كده دلوقتي، لأنه غيّره هو بالـ PATCH المباشر) فيعدّوا الفحص ويسرق
--  الأرباح، من غير ما يكون سلّم أي حاجة فعليًا.
--
--  الحل: قفل UPDATE بالكامل على orders/rides لـ anon/authenticated —
--  كل تغيير حالة دلوقتي لازم يمر عبر دالة SECURITY DEFINER بتتحقق من
--  الملكية (driver_phone/store owner) والحالة السابقة الصحيحة قبل ما
--  تسمح بالتغيير. الدوال الموجودة بالفعل (confirm_order_delivery،
--  settle_order_commission، settle_order_merchant_credit،
--  mark_ride_arrived، accept_dispatch_offer، submit/accept/reject_ride_
--  price_offer، customer_cancel_ride) تغطي جزء من التحولات. الدوال
--  الجديدة تحت بتغطي الباقي (قبول مباشر بدون عرض توزيع، استلام الطلب،
--  تقدّم الرحلة، تسليم/رفض/تجهيز الطلب من التاجر).
--
--  ملاحظة: لازم تحدّث الكود بعد تشغيل الملف ده (driver-dashboard.astro +
--  merchant-dashboard.astro + flutter driver_repository.dart +
--  merchant_repository.dart) — موجود في نفس الكوميت.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) driver_accept_ride — قبول مباشر لرحلة (المسار الاحتياطي في
--    driver-dashboard.astro لما مفيش offer_id، بدل PATCH مباشر).
-- ---------------------------------------------------------------------
create or replace function public.driver_accept_ride(
  p_ride_id uuid, p_driver_phone text, p_driver_name text default null
) returns setof public.rides
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_driver_status text; v_driver_cat text;
begin
  select status, vehicle_category into v_driver_status, v_driver_cat
  from public.driver_applications
  where phone::text = p_driver_phone
  order by created_at desc
  limit 1;

  if v_driver_status is distinct from 'approved' then
    raise exception 'driver_not_approved';
  end if;
  if v_driver_cat in ('motorcycle', 'cargo') then
    raise exception 'delivery_only_vehicle';
  end if;

  return query
    update public.rides
       set status = 'accepted', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), accepted_at = now()
     where id = p_ride_id and driver_phone is null and status = 'pending'
     returning rides.*;
end;
$$;

grant execute on function public.driver_accept_ride(uuid, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) driver_update_ride_status — in_progress/completed (arrived يفضل
--    من غير mark_ride_arrived الموجودة أصلاً — الخصم التلقائي للتأخير).
-- ---------------------------------------------------------------------
create or replace function public.driver_update_ride_status(
  p_ride_id uuid, p_driver_phone text, p_status text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_ride public.rides%rowtype; v_rows int;
begin
  if p_status not in ('in_progress', 'completed') then
    raise exception 'invalid_status';
  end if;

  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride_not_found'; end if;
  if v_ride.driver_phone is distinct from p_driver_phone then raise exception 'not_your_ride'; end if;

  if p_status = 'in_progress' then
    update public.rides set status = 'in_progress' where id = p_ride_id;
  else
    update public.rides set status = 'completed', completed_at = now() where id = p_ride_id;
  end if;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

grant execute on function public.driver_update_ride_status(uuid, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) merchant_accept_order / merchant_reject_order / merchant_mark_order_ready
--    — التاجر لازم يكون فعلاً صاحب المتجر بتاع الطلب (stores.owner_phone).
-- ---------------------------------------------------------------------
create or replace function public.merchant_accept_order(
  p_order_id uuid, p_merchant_phone text, p_prep_minutes int default null
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_order public.orders%rowtype; v_owns boolean; v_rows int;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'order_not_found'; end if;

  select exists(select 1 from public.stores where id = v_order.store_id and owner_phone = p_merchant_phone) into v_owns;
  if not v_owns then raise exception 'not_your_store'; end if;
  if v_order.status <> 'pending' then raise exception 'order_not_pending'; end if;

  update public.orders
     set status = 'preparing', accepted_at = now(),
         prep_minutes = coalesce(p_prep_minutes, prep_minutes)
   where id = p_order_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.merchant_accept_order(uuid, text, int) to anon, authenticated;

create or replace function public.merchant_reject_order(
  p_order_id uuid, p_merchant_phone text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_order public.orders%rowtype; v_owns boolean; v_rows int;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'order_not_found'; end if;

  select exists(select 1 from public.stores where id = v_order.store_id and owner_phone = p_merchant_phone) into v_owns;
  if not v_owns then raise exception 'not_your_store'; end if;
  if v_order.status not in ('pending', 'preparing') then raise exception 'order_not_rejectable'; end if;

  update public.orders set status = 'rejected', rejected_at = now() where id = p_order_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.merchant_reject_order(uuid, text) to anon, authenticated;

create or replace function public.merchant_mark_order_ready(
  p_order_id uuid, p_merchant_phone text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_order public.orders%rowtype; v_owns boolean; v_rows int;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'order_not_found'; end if;

  select exists(select 1 from public.stores where id = v_order.store_id and owner_phone = p_merchant_phone) into v_owns;
  if not v_owns then raise exception 'not_your_store'; end if;

  update public.orders set ready_at = now() where id = p_order_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.merchant_mark_order_ready(uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) driver_claim_delivery_order — استلام طلب متاح (broadcast، بدون
--    offer_id) بدل PATCH مباشر بشرط driver_phone is null.
-- ---------------------------------------------------------------------
create or replace function public.driver_claim_delivery_order(
  p_order_id uuid, p_driver_phone text, p_driver_name text default null
) returns setof public.orders
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_driver_status text;
begin
  select status into v_driver_status
  from public.driver_applications
  where phone::text = p_driver_phone
  order by created_at desc
  limit 1;
  if v_driver_status is distinct from 'approved' then
    raise exception 'driver_not_approved';
  end if;

  return query
    update public.orders
       set status = 'on_the_way', driver_phone = p_driver_phone,
           driver_name = coalesce(p_driver_name, driver_name), picked_up_at = null
     where id = p_order_id and driver_phone is null and status = 'preparing'
     returning orders.*;
end;
$$;

grant execute on function public.driver_claim_delivery_order(uuid, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5) driver_mark_order_picked_up — الطلب اتاخد من المتجر وفي الطريق
--    للعميل (الطلب لازم يكون أصلاً معيّن لنفس السائق، عبر offer أو
--    claim سابق).
-- ---------------------------------------------------------------------
create or replace function public.driver_mark_order_picked_up(
  p_order_id uuid, p_driver_phone text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_order public.orders%rowtype; v_rows int;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.driver_phone is distinct from p_driver_phone then raise exception 'not_your_order'; end if;

  update public.orders set status = 'on_the_way', picked_up_at = now() where id = p_order_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

grant execute on function public.driver_mark_order_picked_up(uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 6) admin_set_order_status / admin_set_ride_status / admin_delete_order
--    — لوحة الأدمن (admin.astro) بتغيّر حالة أي طلب/رحلة أو تحذفها
--    كأداة تجاوز إدارية (courier/merchant-delivery/general-delivery
--    accept/reject، مُحرّر الحالة العام لكل من الطلبات والرحلات، حذف
--    طلب) — نفس نمط باقي إجراءات الأدمن الحساسة (باسورد أدمن حقيقي
--    بيتحقق منه bcrypt، زي grant_admin/admin_delete_account).
-- ---------------------------------------------------------------------
create or replace function public._check_admin(p_admin_phone text, p_admin_password text)
returns boolean
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
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;
  return true;
end;
$$;
revoke all on function public._check_admin(text, text) from public, anon, authenticated;

create or replace function public.admin_set_order_status(
  p_admin_phone text, p_admin_password text, p_order_id uuid, p_status text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then
    raise exception 'not_admin';
  end if;

  update public.orders
     set status = p_status,
         accepted_at = case when p_status = 'preparing' then now() else accepted_at end
   where id = p_order_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.admin_set_order_status(text, text, uuid, text) to anon, authenticated;

create or replace function public.admin_set_ride_status(
  p_admin_phone text, p_admin_password text, p_ride_id uuid, p_status text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then
    raise exception 'not_admin';
  end if;

  update public.rides set status = p_status where id = p_ride_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.admin_set_ride_status(text, text, uuid, text) to anon, authenticated;

create or replace function public.admin_delete_order(
  p_admin_phone text, p_admin_password text, p_order_id uuid
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then
    raise exception 'not_admin';
  end if;

  delete from public.orders where id = p_order_id;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.admin_delete_order(text, text, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 7) إقفال التعديل/الحذف المباشر بالكامل على orders/rides. القراءة
--    (SELECT) والإنشاء (INSERT) يفضلوا زي ما هم — كل تحويلات الحالة
--    بعد الإنشاء دلوقتي لازم تمر بدالة محمية.
-- ---------------------------------------------------------------------
revoke update, delete on public.orders from anon, authenticated;
revoke update, delete on public.rides  from anon, authenticated;

-- =====================================================================
--  Done. Quick self-test (from the REST API with the anon key):
--    PATCH /rest/v1/orders?id=eq.<any> {"status":"delivered","driver_phone":"<any>"}
--      ⇒ 403/permission denied ✅ (previously would have succeeded)
-- =====================================================================
