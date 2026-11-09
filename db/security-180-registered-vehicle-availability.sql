-- =====================================================================
--  وصّلها — #180: تقييد قائمة السيارات اللي العميل يقدر يختارها على
--  السيارات المسجّلة فعليًا عند تسجيل السائقين بس
--
--  security-179 بنى تسعير حقيقي حسب الموديل، لكن القائمة اللي العميل
--  بيختار منها (vehicle_catalog.dart) كانت كتالوج ثابت لـ29 موديل —
--  بغض النظر عن وجود سائق حقيقي بيقود الموديل ده فعلاً أصلاً. لازم
--  العميل يقدر يختار بس من اللي فعلاً متسجل عند تسجيل سائق معتمد.
--
--  driver_applications.vehicle_model كان نص حر (بيكتبه السائق وقت
--  التسجيل)، مش مربوط بـ vehicle_rates — مينفعش نستخدمه للمطابقة
--  الدقيقة. الحل:
--
--  1) عمود جديد driver_applications.vehicle_model_id (مرجع لـ
--     vehicle_rates.id) — ده اللي بقى src/pages/driver.astro بيبعته
--     دلوقتي (كاتالوج select بدل نص حر، للسيارات سيدان/SUV/ميكروباص
--     بس — الدراجات وعربيات النقل برّه نطاق الميزة دي خالص).
--  2) مطابقة تقريبية لمرة واحدة (best-effort) للسائقين المسجلين
--     بالفعل قبل التحديث ده — نص حر زي "تويوتا كورولا" يتطابق مع اسم
--     الموديل في vehicle_rates. أي حد منهم مايتطابقش (زي "شيري اريزو"
--     اللي مش في الكتالوج أصلاً دلوقتي) هيفضل NULL لحد ما يحدّث بياناته
--     عن طريق الفورم الجديد (كاتالوج إجباري من دلوقتي فصاعدًا).
--  3) get_available_vehicle_models(): بترجع بس الموديلات اللي فعلاً
--     عندها سائق واحد على الأقل معتمد ومسجّل بـ vehicle_model_id —
--     ده اللي Flutter هيستخدمه بدل القائمة الثابتة.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.driver_applications
  add column if not exists vehicle_model_id text references public.vehicle_rates(id);

-- مطابقة تقريبية لمرة واحدة — بس للصفوف اللي لسه من غير vehicle_model_id.
update public.driver_applications da
set vehicle_model_id = vr.id
from public.vehicle_rates vr
where da.vehicle_model_id is null
  and da.vehicle_model is not null
  and (
    lower(trim(da.vehicle_model)) = lower(vr.id)
    or da.vehicle_model ilike '%' || vr.name || '%'
    or vr.name ilike '%' || da.vehicle_model || '%'
  );

create or replace function public.get_available_vehicle_models()
returns table(id text, name text, category text, km_per_liter numeric)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select distinct vr.id, vr.name, vr.category, vr.km_per_liter
    from public.vehicle_rates vr
    join public.driver_applications da on da.vehicle_model_id = vr.id
   where da.status = 'approved';
$$;
grant execute on function public.get_available_vehicle_models() to anon, authenticated;
revoke execute on function public.get_available_vehicle_models() from public;
