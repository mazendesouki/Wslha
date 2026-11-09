-- =====================================================================
--  وصّلها — #181: إضافة "شيري اريزو" لكتالوج vehicle_rates
--
--  أول سائق معتمد حقيقي في النظام (غير اختبارات) عنده "شيري اريزو" —
--  مش في الـ29 موديل الأصليين، فـget_available_vehicle_models()
--  (security-180) كانت بترجع صفر صفوف، والعميل مكنش هيلاقي أي سيارة
--  يختارها. إضافة الموديل ده للكتالوج + إعادة تشغيل مطابقة الـbackfill
--  مرة واحدة كفت لربط صف السائق الموجود فعلاً بيه.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
insert into public.vehicle_rates (id, name, category, rate_per_km, km_per_liter)
values ('arrizo', 'شيري اريزو', 'sedan', 9.5, 14.5)
on conflict (id) do nothing;

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
