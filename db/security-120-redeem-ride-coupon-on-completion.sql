-- =====================================================================
--  وصّلها — Security #120: تحويل خصم الكوبون لحظة اكتمال الرحلة فعليًا
--
--  المشكلة (من مراجعة نظام الكوبونات): redeem_coupon كان بينادى من
--  rides_screen.dart فورًا بعد createRide() ينجح — يعني وقت الحجز، مش
--  وقت اكتمال الرحلة. التوثيق الأصلي في security-75 نفسه كان ناوي
--  "بعد إتمام الحجز/الطلب"، بس التنفيذ الفعلي في التطبيق كان بيطبّق
--  الخصم فورًا. ده كان بيفتح باب: احجز بكود خصم → خد الاسترداد في
--  المحفظة فورًا → اعمل cancel للرحلة قبل ما سائق يوصل → خد الاسترداد
--  من غير ما تدفع أو تاخد رحلة فعليًا، وتقدر تكرر ده لحد حد الاستخدام
--  بتاع الكود (usage_limit/per_user_limit)، لأن مفيش أي "تراجع" عن
--  الاسترداد عند الإلغاء في أي مكان في المشروع.
--
--  الإصلاح: الحجز بقى يسجّل الكود المُطبّق بس على صف الرحلة (عمود
--  coupon_code جديد، من غير أي تحويل فعلي للمحفظة وقت الحجز). التحويل
--  الفعلي بقى يحصل من تريجر على rides نفسه، لما status يتحول لـ
--  'completed' فعليًا — وده التحديث الوحيد اللي ممكن يحصل لـ status
--  (UPDATE مقفول تمامًا عن anon/authenticated من security-48، كل تحديث
--  لازم يعدي بدالة SECURITY DEFINER زي driver_update_ride_status)، فمفيش
--  طريق تاني لحد يشغّل الاسترداد غير إكمال رحلة حقيقية فعلاً. رحلة
--  اتلغت أبدًا مش توصل لـ status='completed'، فالتريجر مايتفعّلش ليها
--  خالص — مفيش استرداد، مفيش استغلال.
--
--  التريجر مُغلّف بـ exception handler شامل (begin/exception) عشان أي
--  خطأ في منطق الكوبون (كود انتهت صلاحيته بين وقت الحجز والاكتمال مثلاً)
--  أبدًا ما يمنع تحديث حالة الرحلة لـ completed نفسه — فشل الخصم صامت،
--  زي ما كان بالظبط مع catch(_) القديم في rides_screen.dart.
--
--  redeem_coupon نفسه من غير تغيير (لسه موجود لو احتاج استخدامه مكان
--  تاني زي الطلبات لاحقًا)، وبرضو بيحمي نفسه من استدعاء مكرر لنفس
--  reference_id عن طريق unique(service_type, reference_id) — فحتى لو
--  التريجر اتفعّل مرتين لأي سبب (لا ينفعش يحصل أصلاً، لأن الشرط تحت
--  يتطلب انتقال فعلي من حالة غير completed لـ completed) هو مؤمّن.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.rides add column if not exists coupon_code text;

create or replace function public._redeem_ride_coupon_on_completion()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_check record;
begin
  if new.status = 'completed' and old.status is distinct from 'completed' and new.coupon_code is not null then
    begin
      if exists (
        select 1 from public.coupon_redemptions
        where service_type = 'ride' and reference_id = new.id::text
      ) then
        return new; -- already redeemed (shouldn't happen, but idempotent)
      end if;

      select * into v_check from public._check_coupon(new.coupon_code, new.customer_phone, new.fare::numeric, 'ride');
      if v_check.ok then
        insert into public.coupon_redemptions (coupon_id, phone, service_type, reference_id, discount_amount)
        values (v_check.coupon_id, new.customer_phone, 'ride', new.id::text, v_check.discount_amount);

        perform public.add_wallet_balance(new.customer_phone, v_check.discount_amount);
        insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
        values (
          'wtx-coupon-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
          new.customer_phone, v_check.discount_amount, 'coupon_discount', new.id::text,
          'خصم كود ' || upper(trim(new.coupon_code)), now()
        );
      end if;
    exception when others then
      -- فشل منطق الكوبون أبدًا ميوقفش اكتمال الرحلة نفسها.
      null;
    end;
  end if;
  return new;
end;
$$;

create or replace trigger trg_redeem_ride_coupon_on_completion
  after update on public.rides
  for each row execute function public._redeem_ride_coupon_on_completion();
