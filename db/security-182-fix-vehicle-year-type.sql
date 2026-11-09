-- =====================================================================
--  وصّلها — #182: تصحيح نوع vehicle_year في get_available_driver_vehicles()
--
--  الدالة كانت معرّفة ترجع vehicle_year كـtext رغم إن العمود الأصلي في
--  driver_applications من نوع integer — فبوستجرس كان بيحوّله لنص تلقائي.
--  شاشة المطار في فلاتر (airport_repository.dart) بتعمل
--  `(r['vehicle_year'] as num?)` على القيمة الراجعة، وده كان بيرمي
--  استثناء (TypeError) مع أي نص زي "2024" بدل رقم — الاستثناء ده مكنش
--  متلقّط، فـ_loadVehicles() كانت بتفضل stuck على "loading" للأبد
--  (لودر بيلف من غير ما يختفي أبداً في خطوة "اختيار السيارة").
--
--  آمن لإعادة التشغيل.
-- =====================================================================
drop function if exists public.get_available_driver_vehicles();
create function public.get_available_driver_vehicles()
returns table(vehicle_category text, vehicle_model text, vehicle_year integer)
language sql
security definer
set search_path = public, extensions
as $$
  select vehicle_category, vehicle_model, vehicle_year
    from public.driver_applications
   where status = 'approved';
$$;
grant execute on function public.get_available_driver_vehicles() to anon, authenticated;
