-- =====================================================================
--  وصّلها — Security #178: تضييق RPCs الفلاتر المفتوحة بالكامل
--  (upsert_driver_location, upsert_device_token) + bucket documents
--
--  اتكشف ضمن مراجعة تطبيق الفلاتر (customer/driver/merchant):
--
--  1) upsert_driver_location(p_driver_phone, ...): مفروض تتنادى بس من
--     السائق نفسه (location ping كل كام ثانية أثناء الرحلة) — وفيه
--     بالفعل بروكسي محمي بـ token (/api/driver/location، IDOR fix
--     Phase 1/2) بتجرّبه Flutter الأول دايمًا. لكن الـ RPC المباشرة
--     (fallback لمن لسه معندوش session token — زي ما اتأكد النهارده إن
--     usage الـ token لسه صفر فعليًا في الإنتاج) كانت بتثق بأي
--     p_driver_phone من غير أي تحقق، يعني أي حد يقدر "يزوّر" موقع أي
--     سائق حقيقي على خريطة التتبع الحية بتاعة العميل. الحل المؤقت (لحد
--     ما استخدام الـ token يزيد): لازم p_driver_phone يبقى سائق معتمد
--     فعلاً (driver_applications.status='approved') — نفس البوابة
--     المستخدمة أصلاً في accept_dispatch_offer (security-15). ده مش
--     إصلاح IDOR كامل (سائق معتمد لسه يقدر يزوّر سائق معتمد تاني)، بس
--     بيقفل الباب قدام أي حد مش سائق خالص.
--
--  2) upsert_device_token(p_phone, p_token, ...): نفس المشكلة —
--     p_phone من غير أي تحقق، يعني أي حد يقدر يسجّل device token بتاعه
--     على رقم أي حساب حقيقي ويحوّل إشعاراته لنفسه. مفيش بروكسي محمي
--     بـ token ليها لسه (مختلف عن location) — اتضاف هنا
--     /api/push/register.ts (نفس نمط /api/driver/location)، وبُنيت
--     Flutter push.dart عشان تجرّبه الأول. الـ RPC المباشرة (fallback)
--     بقت على الأقل بتتحقق إن p_phone فعلاً حساب موجود (مش رقم وهمي) —
--     نفس تضييق محدود زي فوق، الإصلاح الكامل مرتبط بتبني الـ token.
--
--  3) bucket "documents": نفس فئة مشكلة bucket "promotions" (security-
--     175) — رفع مفتوح لأي حد، لكن هنا الرفع ده سلوك مقصود (توثيق
--     KYC أثناء التسجيل قبل ما يبقى للمستخدم حساب مفعّل أصلاً، فمفيش
--     كلمة مرور ممكن نطلبها). الحل: تقييد نوع الملفات المسموحة لصور
--     + PDF بس (بدل أي نوع ملف)، بدل قفل الرفع خالص، عشان الفلو
--     الحقيقي (تسجيل سائق/تاجر) يفضل شغّال. حجم الملف كان مظبوط بالفعل
--     (50MB). اتنضفت كمان policies مكررة (duplicate) كانت زيادة عن
--     الحاجة.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.upsert_driver_location(
  p_driver_phone text, p_lat double precision, p_lng double precision,
  p_driver_name text default null, p_heading double precision default null,
  p_is_online boolean default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not exists (
    select 1 from public.driver_applications
     where status = 'approved'
       and phone in (p_driver_phone,
                     case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end,
                     case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end)
  ) then
    return;
  end if;

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

create or replace function public.upsert_device_token(p_phone text, p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_phone is null or length(trim(p_phone)) = 0 then
    raise exception 'رقم الهاتف مطلوب';
  end if;
  if p_token is null or length(trim(p_token)) = 0 then
    raise exception 'التوكن مطلوب';
  end if;
  if p_platform not in ('android','ios') then
    raise exception 'منصة غير معروفة: %', p_platform;
  end if;

  if not exists (
    select 1 from public.accounts
     where phone in (p_phone,
                     case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end,
                     case when p_phone like '0%'   then '+2'||p_phone           else p_phone end)
  ) then
    return;
  end if;

  insert into public.device_tokens (id, phone, token, platform, updated_at)
  values ('dt-' || substr(md5(p_phone || p_token), 1, 24), p_phone, p_token, p_platform, now())
  on conflict (phone, token)
  do update set platform = excluded.platform, updated_at = now();
end;
$$;

-- bucket documents: تقييد نوع الملفات لصور + PDF بس (نفس الأنواع اللي
-- driver.astro's handleUpload() أصلًا بتقبلها client-side) — حجم 50MB
-- كان مظبوط بالفعل.
update storage.buckets
   set allowed_mime_types = array['image/jpeg','image/jpg','image/png','image/webp','application/pdf']
 where id = 'documents';

-- تنضيف policies مكررة (أسماء "policy  documents flreew_0/_1" — زيادة
-- عن الحاجة فوق "anon upload documents"/"public read documents"
-- الأوضح أسماءً، بنفس السلوك بالظبط).
drop policy if exists "policy  documents flreew_0" on storage.objects;
drop policy if exists "policy  documents flreew_1" on storage.objects;
