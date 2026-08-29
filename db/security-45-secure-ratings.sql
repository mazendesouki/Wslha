-- =====================================================================
--  وصّلها — Security #45: قفل جدول ratings عن الإدراج المباشر
--
--  اكتُشف في نفس المراجعة الأمنية اللي لقت ثغرة المحفظة: جدول ratings
--  كان مفتوح للإدراج المباشر (INSERT) لأي حد معاه الـ anon key، بلا أي
--  ربط بطلب/رحلة حقيقية — أي حد يقدر يضيف تقييم 1 أو 5 نجوم وهمي على
--  أي سائق/عميل/متجر برقم جواله بس، من غير ما يكون فعلاً عمل رحلة أو
--  طلب معاه.
--
--  الحل: 3 دوال SECURITY DEFINER محل الإدراج المباشر، كل واحدة بتتحقق
--  إن فيه رحلة/طلب حقيقي مكتمل يربط الطرفين قبل ما تسمح بالتقييم:
--   1) submit_ride_rating         — العميل يقيّم السائق بعد رحلة completed.
--   2) submit_customer_rating     — السائق يقيّم العميل بعد رحلة/طلب
--                                   completed/delivered وهو صاحبه فعلاً.
--   3) submit_order_rating        — تقييم المتجر (+السائق اختياريًا) بعد
--                                   طلب delivered، بكود الطلب (track.astro
--                                   بيسمح بالتتبع من غير تسجيل دخول، فالتحقق
--                                   هنا مبني على معرفة كود طلب حقيقي +
--                                   الحالة delivered، و store_id/driver_phone
--                                   بيتاخدوا من صف الطلب نفسه مش من العميل
--                                   عشان محدش يقيّم متجر/سائق مش بتاع طلبه).
--  الثلاثة فيهم حارس ضد التكرار (نفس الرحلة/الطلب متتقيّمش مرتين).
--
--  ملاحظة: لازم تحدّث الكود بعد تشغيل الملف ده (track.astro +
--  driver-dashboard.astro + flutter ratings_repository.dart) — موجود في
--  نفس الكوميت.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) submit_ride_rating — العميل يقيّم السائق بعد رحلة مكتملة.
-- ---------------------------------------------------------------------
create or replace function public.submit_ride_rating(
  p_ride_id uuid, p_customer_phone text, p_rating int,
  p_comment text default null, p_tags text[] default null
) returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_ride public.rides%rowtype; v_id text;
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'invalid_rating'; end if;

  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride_not_found'; end if;
  if v_ride.customer_phone is distinct from p_customer_phone then raise exception 'not_your_ride'; end if;
  if v_ride.status <> 'completed' then raise exception 'ride_not_completed'; end if;

  if exists (select 1 from public.ratings where ride_id = p_ride_id::text and rated_by = 'customer') then
    raise exception 'already_rated';
  end if;

  v_id := 'rt-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6);
  insert into public.ratings (id, driver_phone, customer_phone, rating, comment, service_type, ride_id, rated_by, tags, created_at)
  values (v_id, v_ride.driver_phone, p_customer_phone, p_rating, p_comment, coalesce(v_ride.ride_type, 'ride'), p_ride_id::text, 'customer', p_tags, now());

  return v_id;
end;
$$;

grant execute on function public.submit_ride_rating(uuid, text, int, text, text[]) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) submit_customer_rating — السائق يقيّم العميل بعد رحلة/طلب مكتمل هو
--    فعلاً اللي نفّذه (driver_phone بيتاخد من الصف نفسه مش من الاستدعاء).
-- ---------------------------------------------------------------------
create or replace function public.submit_customer_rating(
  p_driver_phone text, p_service_type text, p_reference_id uuid, p_rating int,
  p_comment text default null, p_tags text[] default null
) returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_customer_phone text; v_id text;
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'invalid_rating'; end if;

  if p_service_type = 'delivery' then
    select customer_phone into v_customer_phone from public.orders
     where id = p_reference_id and driver_phone = p_driver_phone and status = 'delivered';
  else
    select customer_phone into v_customer_phone from public.rides
     where id = p_reference_id and driver_phone = p_driver_phone and status = 'completed';
  end if;

  if v_customer_phone is null then raise exception 'not_your_trip'; end if;

  if exists (select 1 from public.ratings where ride_id = p_reference_id::text and rated_by = 'driver') then
    raise exception 'already_rated';
  end if;

  v_id := 'rt-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6);
  insert into public.ratings (id, driver_phone, customer_phone, rating, comment, service_type, ride_id, rated_by, tags, created_at)
  values (v_id, p_driver_phone, v_customer_phone, p_rating, p_comment, p_service_type, p_reference_id::text, 'driver', p_tags, now());

  return v_id;
end;
$$;

grant execute on function public.submit_customer_rating(text, text, uuid, int, text, text[]) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) submit_order_rating — تقييم متجر/سائق بكود طلب delivered حقيقي.
--    track.astro بيسمح بالتتبع/التقييم من غير تسجيل دخول أصلاً، فالضمان
--    هنا هو معرفة كود طلب حقيقي + حالته delivered، مع أخذ store_id/
--    driver_phone من صف الطلب نفسه (مش من العميل) — يمنع تقييم متجر/سائق
--    غير المرتبط فعليًا بالطلب.
-- ---------------------------------------------------------------------
create or replace function public.submit_order_rating(
  p_order_code text, p_store_rating int, p_driver_rating int default null,
  p_comment text default null, p_tags text[] default null
) returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_order public.orders%rowtype; v_id text;
begin
  if p_store_rating is null or p_store_rating < 1 or p_store_rating > 5 then raise exception 'invalid_rating'; end if;
  if p_driver_rating is not null and (p_driver_rating < 1 or p_driver_rating > 5) then raise exception 'invalid_rating'; end if;

  select * into v_order from public.orders where code = p_order_code for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.status <> 'delivered' then raise exception 'order_not_delivered'; end if;

  if exists (select 1 from public.ratings where order_code = p_order_code) then
    raise exception 'already_rated';
  end if;

  v_id := 'rt-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6);
  insert into public.ratings (id, order_code, store_id, driver_phone, store_rating, driver_rating, comment, tags, created_at)
  values (v_id, p_order_code, v_order.store_id, v_order.driver_phone, p_store_rating, p_driver_rating, p_comment, p_tags, now());

  if v_order.store_id is not null then
    perform public.update_store_rating(v_order.store_id, p_store_rating);
  end if;

  return v_id;
end;
$$;

grant execute on function public.submit_order_rating(text, int, int, text, text[]) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) إقفال الإدراج المباشر على ratings — التقييم دلوقتي لازم يمر بواحدة
--    من الدوال التلاتة فوق.
-- ---------------------------------------------------------------------
drop policy if exists ratings_insert_all on public.ratings;
revoke insert on public.ratings from public, anon, authenticated;

-- =====================================================================
--  Done. Quick self-test (optional, from the REST API with the anon key):
--    POST /rest/v1/rpc/submit_ride_rating
--      {"p_ride_id":"<uuid ما ليك>","p_customer_phone":"<رقمك>","p_rating":5}
--      ⇒ exception not_your_ride (أو ride_not_found) ✅
-- =====================================================================
