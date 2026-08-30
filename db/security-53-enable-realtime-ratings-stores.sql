-- =====================================================================
--  وصّلها — Security #53: تفعيل التحديث اللحظي لجداول التقييمات والمتاجر
--
--  السبب الحقيقي وراء "التقييم مش بيتحدّث في الوقت الفعلي بعد كل رحلة":
--  نفس فئة الغلطة اللي اتصلّحت في security-38 (ride_price_offers) —
--  جدولي ratings و stores كانوا موجودين ومحدَّثين صح في قاعدة البيانات،
--  بس محدّش ضافهم لقائمة الجداول اللي Supabase Realtime بيبثّها لحظيًا
--  (supabase_realtime publication)، فأي .stream()/قناة realtime عليهم
--  كانت هتفضل ساكنة أبديًا حتى لو صف اتسجّل أو اتحدّث فعليًا — تحديث
--  التقييم كان محتاج يقفل التطبيق ويفتحه (أو ينتقل بين التابات) عشان
--  يجيب البيانات الجديدة بقراءة عادية، مش لحظيًا زي المطلوب.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'ratings'
  ) then
    alter publication supabase_realtime add table public.ratings;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'stores'
  ) then
    alter publication supabase_realtime add table public.stores;
  end if;
end $$;
