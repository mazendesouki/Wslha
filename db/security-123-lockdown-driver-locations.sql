-- =====================================================================
--  وصّلها — Security #123: قفل driver_locations
--
--  من مراجعة أمنية شاملة: driver_locations كان عليه 4 policies مختلفة
--  كل واحدة منها USING(true)/WITH CHECK(true) (بما فيها واحدة catch-all
--  "FOR ALL") — يعني أي حد بالـ anon key يقدر:
--   - يشوف موقع GPS الحي لكل سائق في أي وقت (مش بس وقت ما يكون متوصل
--     لرحلة عميل فعلية).
--   - يزوّر موقع أي سائق (PATCH برقم تليفونه)، يطفّيه فجأة (DoS على
--     أهليته للتوزيع)، أو يمسح صفه بالكامل.
--
--  الإصلاح:
--   - الكتابة (INSERT/UPDATE/DELETE) بقت مقفولة بالكامل (ALTER POLICY
--     ...USING(false)) — بديلها دالتين SECURITY DEFINER بس.
--   - القراءة اتضيّقت لـ is_online=true بس (مش قفل كامل — مفيش JWT
--     حقيقي في المشروع يسمح بتحديدها "بس للعميل المرتبط برحلة فعلية"
--     من غير ما يكسر التتبع اللحظي الحالي؛ نفس المقايضة المقبولة فعليًا
--     مع ride_messages/ride_price_offers). النتيجة العملية: مستحيل دلوقتي
--     تلاحق سائق بعد ما يسجّل خروج أو تشوف تاريخ مواقعه.
--
--  ⚠️ دالتين upsert منفصلتين بالاسم عمدًا (upsert_driver_location الأصلية
--  6 بارامترات، وupsert_driver_location_with_job الأوسع 10 بارامترات) —
--  لو زوّدت بارامترات على upsert_driver_location نفسها بنفس الاسم،
--  PostgREST/Postgres بيرفض أي استدعاء بـ 6 بارامترات بس بغلطة "function
--  ... is not unique" لأنه مش عارف يختار بين الاوفرلودين. اتجرب هنا
--  فعليًا وبان الخطأ ده قبل التثبيت على الاسم المنفصل.
--
--  آمن لإعادة التشغيل (ALTER POLICY يفضل يشتغل حتى لو اتنفذ قبل كده).
-- =====================================================================
set search_path = public, extensions;

alter policy driver_loc_all on public.driver_locations using (false) with check (false);
alter policy driver_locations_upsert_all on public.driver_locations with check (false);
alter policy driver_locations_update_all on public.driver_locations using (false) with check (false);
alter policy driver_locations_delete_all on public.driver_locations using (false);
alter policy driver_locations_select_all on public.driver_locations using (is_online = true);

create or replace function public.upsert_driver_location(
  p_driver_phone text, p_lat double precision, p_lng double precision,
  p_driver_name text default null, p_heading double precision default null, p_is_online boolean default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.driver_locations (driver_phone, driver_name, lat, lng, heading, is_online, updated_at)
  values (p_driver_phone, p_driver_name, p_lat, p_lng, p_heading, coalesce(p_is_online, true), now())
  on conflict (driver_phone) do update set
    driver_name = coalesce(excluded.driver_name, public.driver_locations.driver_name),
    lat = excluded.lat,
    lng = excluded.lng,
    heading = coalesce(excluded.heading, public.driver_locations.heading),
    is_online = coalesce(excluded.is_online, public.driver_locations.is_online),
    updated_at = now();
end;
$$;
grant execute on function public.upsert_driver_location(text, double precision, double precision, text, double precision, boolean) to anon, authenticated;

-- نفس اللي فوق + ride_id/current_order_id — لاستخدام driver-dashboard.astro
-- (upsertLocation() بتبعتهم كمان). p_clear_ride/p_clear_order لأن null
-- من العميل معناه عادةً "محصلش تغيير" (pingLocation ميبعتهمش خالص)،
-- فلازم تمييز واضح لما السائق يسيب رحلة/طلب فعليًا (null حقيقي مقصود).
create or replace function public.upsert_driver_location_with_job(
  p_driver_phone text, p_lat double precision, p_lng double precision,
  p_driver_name text default null, p_heading double precision default null, p_is_online boolean default null,
  p_ride_id uuid default null, p_current_order_id text default null, p_clear_ride boolean default false,
  p_clear_order boolean default false
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.driver_locations (driver_phone, driver_name, lat, lng, heading, is_online, ride_id, current_order_id, updated_at)
  values (
    p_driver_phone, p_driver_name, p_lat, p_lng, p_heading, coalesce(p_is_online, true),
    p_ride_id, p_current_order_id, now()
  )
  on conflict (driver_phone) do update set
    driver_name = coalesce(excluded.driver_name, public.driver_locations.driver_name),
    lat = excluded.lat,
    lng = excluded.lng,
    heading = coalesce(excluded.heading, public.driver_locations.heading),
    is_online = coalesce(excluded.is_online, public.driver_locations.is_online),
    ride_id = case when p_clear_ride then null when p_ride_id is not null then p_ride_id else public.driver_locations.ride_id end,
    current_order_id = case when p_clear_order then null when p_current_order_id is not null then p_current_order_id else public.driver_locations.current_order_id end,
    updated_at = now();
end;
$$;
grant execute on function public.upsert_driver_location_with_job(text, double precision, double precision, text, double precision, boolean, uuid, text, boolean, boolean) to anon, authenticated;

create or replace function public.set_driver_offline(p_driver_phone text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.driver_locations set is_online = false, updated_at = now() where driver_phone = p_driver_phone;
end;
$$;
grant execute on function public.set_driver_offline(text) to anon, authenticated;
