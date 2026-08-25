-- =====================================================================
--  وصّلها — Security #38: تفعيل التحديث اللحظي على جدول عروض أسعار الرحلات
--
--  السبب الحقيقي وراء "العرض مش بيظهر للعميل": جدول ride_price_offers
--  الجديد (security-35) اتعمل عادي، بس محدّش ضافه لقائمة الجداول اللي
--  Supabase Realtime بيبثّها لحظيًا (supabase_realtime publication) —
--  زي ما اتعمل وقتها بالظبط لجداول rides/orders/driver_locations في
--  الإعداد الأساسي (supabase-schema.sql). من غير الخطوة دي، كل
--  .stream() في التطبيق على الجدول ده (عند العميل والسائق) كان بيفضل
--  فاضي أبديًا حتى لو الصف اتسجّل فعليًا في قاعدة البيانات — نفس فئة
--  الغلطة، مش خطأ برمجي في كود التطبيق.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'ride_price_offers'
  ) then
    alter publication supabase_realtime add table public.ride_price_offers;
  end if;
end $$;
