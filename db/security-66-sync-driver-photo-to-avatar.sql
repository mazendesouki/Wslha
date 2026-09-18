-- =====================================================================
--  وصّلها — Security #66: ربط صورة السائق وقت التسجيل بصورة البروفايل
--
--  driver_applications.driver_photo_url (السيلفي وقت التسجيل، يُقرأ فقط
--  من الأدمن والعميل بعد قبول السائق للرحلة) كان منفصل تمامًا عن
--  accounts.avatar_url (الصورة اللي شاشة "حسابي" بتاعة السائق بتعرضها
--  وبيقدر يغيّرها بنفسه من التطبيق) — لا علاقة بينهم، ولا أي كود كان
--  بينسخ من التاني. النتيجة: صورة مختلفة تظهر لشاشة حسابي عن اللي
--  بتظهر للعميل.
--
--  الحل: تريجر بينسخ driver_photo_url لـ avatar_url أول ما السائق
--  يتم اعتماده (status='approved')، بس لو avatar_url لسه فاضي — عشان
--  لو السائق غيّر صورته بنفسه بعد كده من حسابي، النسخة دي متعملش
--  overwrite لاختياره. الـ Flutter side (ride_repository.dart
--  fetchDriverProfile) بيفضّل accounts.avatar_url لو موجود عند عرض
--  صورة السائق للعميل، فبعد المزامنة دي الاتنين بيبقوا نفس الصورة
--  من الأول، وبعدين يفضلوا متزامنين لأن العميل بيشوف نفس الصورة
--  المحدّثة دايمًا.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.sync_driver_photo_to_avatar()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.status = 'approved' and new.driver_photo_url is not null then
    update public.accounts
    set avatar_url = new.driver_photo_url
    where phone = new.phone and avatar_url is null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_driver_photo_to_avatar on public.driver_applications;
create trigger trg_sync_driver_photo_to_avatar
after insert or update of status, driver_photo_url on public.driver_applications
for each row
execute function public.sync_driver_photo_to_avatar();

-- تصحيح فوري للسائقين المعتمدين بالفعل قبل تشغيل الملف ده.
update public.accounts a
set avatar_url = da.driver_photo_url
from public.driver_applications da
where da.phone = a.phone
  and da.status = 'approved'
  and da.driver_photo_url is not null
  and a.avatar_url is null;
