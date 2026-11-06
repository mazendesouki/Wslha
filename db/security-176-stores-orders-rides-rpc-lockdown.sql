-- =====================================================================
--  وصّلها — Security #176: تأمين تلات دوال كانت متاحة مباشرة لـ anon
--  بتلمس stores/orders/rides من غير أي تحقق هوية
--
--  اتكشف ضمن مراجعة أعمق لكل الدوال اللي بتلمس stores/orders/rides —
--  مش قفل الجداول بس (اللي خلص في security-171/172/173)، لأن دوال
--  SECURITY DEFINER بتتجاوز grants/RLS الجدول تمامًا، فممكن تفضل ثغرة
--  حقيقية حتى بعد قفل الجدول نفسه.
--
--  1) update_store_rating(p_store_id, p_new_rating): المفروض تُستخدم
--     داخليًا بس من submit_order_rating بعد التحقق من طلب حقيقي
--     delivered — لكنها كانت EXECUTE-granted لـ anon/authenticated/
--     PUBLIC بشكل مستقل، من غير أي تحقق إطلاقًا. أي حد يقدر يناديها
--     مباشرة ويعبث بتقييم أي متجر (rating/reviews) براحته. الحل: سحب
--     الصلاحية بالكامل — submit_order_rating نفسها SECURITY DEFINER
--     فهتفضل تقدر تناديها داخليًا زي _check_admin مع admin_* (مفيش
--     GRANT مباشر لـ anon أصلاً، وده شغال تمام).
--
--  2) _apply_first_order_coupon(p_phone, p_service_type, p_reference_id,
--     p_amount): المفروض تُستخدم بس من trigger داخلي (security-121) بعد
--     ما يبعت بيانات الصف الحقيقي (new.customer_phone/new.id/new.fare).
--     كانت EXECUTE-granted لـ anon/authenticated/PUBLIC بشكل مستقل —
--     بتتحقق بس إن الرقم مفيش له طلبات قبل كده، من غير أي تحقق إن
--     p_reference_id ده طلب حقيقي بتاع الرقم، وبتثق في p_amount زي ما هو.
--     استغلال: رقم جديد + reference_id مُلفّق + amount مُضخّم = رصيد
--     محفظة مجاني عبر add_wallet_balance. الحل: سحب الصلاحية بالكامل،
--     نفس منطق update_store_rating فوق.
--
--  3) lookup_order_by_code(p_code): المستخدمة بالفعل في track.astro
--     للتتبع العام بالكود (من غير تسجيل دخول — سلوك مقصود، هتفضل
--     EXECUTE-granted لـ anon). لكنها كانت بترجع كل حقول orders تقريبًا
--     (driver_phone/driver_name + إحداثيات دقيقة للعميل والمتجر + طريقة
--     الدفع + ملخص الأوردر) — أكتر بكتير من اللي صفحة التتبع العامة
--     فعلاً بتعرضه (اتأكد بمراجعة track.astro: بتستخدم بس status/code/
--     store_name/store_emoji/area/address/driver_name/driver_phone/total/
--     store_lat/store_lng). وبما إن كود الطلب (WSL-<year>-<6 digits>)
--     قابل للتخمين (مليون احتمال بالسنة)، ده تسريب بيانات حقيقي لمن
--     يخمّن كود. الحل: تضييق الأعمدة المرجعة للي فعلاً مستخدم بس، بدون
--     لمس الـ grant (التتبع العام لازم يفضل شغّال من غير تسجيل دخول).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

revoke execute on function public.update_store_rating(text, integer) from public, anon, authenticated;
grant execute on function public.update_store_rating(text, integer) to service_role;

revoke execute on function public._apply_first_order_coupon(text, text, text, numeric) from public, anon, authenticated;
grant execute on function public._apply_first_order_coupon(text, text, text, numeric) to service_role;

-- CREATE OR REPLACE can't change an existing function's return columns —
-- must drop first.
drop function if exists public.lookup_order_by_code(text);

create function public.lookup_order_by_code(p_code text)
returns table(
  id uuid, code text, status text,
  store_name text, store_emoji text, store_id text,
  driver_phone text, driver_name text,
  address text, area text, total numeric,
  store_lat double precision, store_lng double precision
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select id, code, status,
         store_name, store_emoji, store_id,
         driver_phone, driver_name,
         address, area, total,
         store_lat, store_lng
    from public.orders
   where code = p_code
   limit 1;
$$;
grant execute on function public.lookup_order_by_code(text) to anon, authenticated;
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default (same gap caught in
-- security-167) — revoke it explicitly since this function is meant to be
-- callable through anon/authenticated only.
revoke execute on function public.lookup_order_by_code(text) from public;
