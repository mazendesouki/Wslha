-- =====================================================================
--  وصّلها — Security #121: نفس إصلاح #120، بس للخصم التلقائي لأول رحلة/طلب
--
--  security-105 (الخصم التلقائي لأول رحلة/طلب) كان شغّال بنفس عيب
--  security-75 اليدوي اللي اتصلح في security-120: الكوبون التلقائي كان
--  بيتطبّق على AFTER INSERT — يعني فور إنشاء الرحلة/الطلب، مش بعد
--  اكتمالها فعليًا. أي كوبون أدمن مفعّل عليه auto_apply_first_order
--  كان بيفتح نفس باب الاستغلال: احجز (أول رحلة/طلب) → خد الاسترداد
--  التلقائي فورًا → اعمل cancel قبل ما السائق يوصل → خد الاسترداد من
--  غير أي رحلة/طلب حقيقي. مانجينهاش في الإصلاح الأول لأنها trigger
--  منفصلة بالكامل عن redeem_coupon.
--
--  الإصلاح: نفس المبدأ — التريجر بقى يتفعّل عند status='completed'
--  (rides) أو status='delivered' (orders) بدل الإنشاء، ومحاط بـ
--  exception handler شامل عشان فشل منطق الكوبون أبدًا ما يوقف تحديث
--  حالة الرحلة/الطلب نفسه (نفس احتياط security-120). منطق
--  _apply_first_order_coupon نفسه من غير تغيير — لسه بيحمي نفسه من
--  ازدواج عن طريق unique(service_type, reference_id) الموجود من
--  security-75، فلو كوبون يدوي اتطبق على نفس الرحلة الكوبون التلقائي
--  هيترفض بأمان (unique_violation متحمّل بالفعل في الدالة).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public._trg_first_order_coupon_ride()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    begin
      perform public._apply_first_order_coupon(new.customer_phone, 'ride', new.id::text, new.fare);
    exception when others then
      null; -- فشل الكوبون التلقائي أبدًا ما يوقف اكتمال الرحلة
    end;
  end if;
  return new;
end;
$$;

create or replace trigger trg_first_order_coupon_ride
  after update on public.rides
  for each row execute function public._trg_first_order_coupon_ride();

create or replace function public._trg_first_order_coupon_order()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.status = 'delivered' and old.status is distinct from 'delivered' then
    begin
      perform public._apply_first_order_coupon(new.customer_phone, 'delivery', new.id::text, new.total);
    exception when others then
      null;
    end;
  end if;
  return new;
end;
$$;

create or replace trigger trg_first_order_coupon_order
  after update on public.orders
  for each row execute function public._trg_first_order_coupon_order();
