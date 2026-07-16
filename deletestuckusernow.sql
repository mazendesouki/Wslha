-- حذف فوري لحساب "شريف رؤوف" (01010785167) اللي فشل حذفه من لوحة الأدمن —
-- عشان بيانات مرتبطة في جداول محتاجة تتنضّف الأول (points/wallets/إلخ).
-- ملاحظة: بعد ما تنقل ADMINDELETEFIX.astro وتنشره، الحذف من لوحة الأدمن
-- نفسها هيشتغل تلقائيًا بدون الحاجة لهذا الملف مرة تانية.
set search_path = public, extensions;

delete from public.driver_applications  where phone = '01010785167';
delete from public.merchant_applications where phone = '01010785167';
delete from public.driver_locations     where driver_phone = '01010785167';
delete from public.wallet_transactions  where phone = '01010785167';
delete from public.rides                where driver_phone = '01010785167';
delete from public.rides                where customer_phone = '01010785167';
delete from public.orders               where customer_phone = '01010785167';
delete from public.points               where phone = '01010785167';
delete from public.point_transactions   where phone = '01010785167';
delete from public.wallets              where phone = '01010785167';
delete from public.push_subscriptions   where phone = '01010785167';
delete from public.accounts             where phone = '01010785167';
