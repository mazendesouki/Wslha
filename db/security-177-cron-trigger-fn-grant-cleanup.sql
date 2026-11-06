-- =====================================================================
--  وصّلها — Security #177: سحب EXECUTE من anon/authenticated/PUBLIC عن
--  دوال داخلية (pg_cron/triggers بس) مش المفروض تتنادى مباشرة أبدًا
--
--  الدوال دي كلها SECURITY DEFINER، بدون أي parameters، والمفروض تتنادى
--  بس من pg_cron (postgres) أو من trigger داخلي على stores/orders/rides —
--  لكنها كانت EXECUTE-granted لـ anon/authenticated/PUBLIC زي أي RPC
--  عادي. مفيش تسريب بيانات مباشر (مفيش parameters بترجع حاجة حساسة)،
--  لكن أي حد يقدر يناديها براحته وقت ما يحب — إزعاج/استغلال (مثلاً يفرض
--  إشعارات/تذكيرات تتبعت بدري، أو يشغّل sweep الديسباتش براحته).
--
--  اتأكد (grep على src/ وflutter_app/) إن مفيش أي كود عميل بينادي أي
--  واحدة من دول مباشرة — كل الاستخدامات الحقيقية عبر pg_cron أو triggers،
--  اللي مش محتاجة GRANT صريح أصلاً (pg_cron بيشغّل كـ postgres، والـ
--  triggers بتتنفذ تلقائيًا من غير فحص EXECUTE على الدور اللي عمل الـ
--  statement). السحب هنا بس بيقفل الباب على الاستدعاء المباشر عبر REST.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
revoke execute on function public.activate_scheduled_rides() from public, anon, authenticated;
revoke execute on function public.generate_recurring_rides() from public, anon, authenticated;
revoke execute on function public.dispatch_sweep_expired() from public, anon, authenticated;
revoke execute on function public.check_cancellation_rate_alert() from public, anon, authenticated;
revoke execute on function public.check_stuck_dispatch_alert() from public, anon, authenticated;
revoke execute on function public.escalate_cash_reminders() from public, anon, authenticated;
revoke execute on function public.notify_customer_ride_accepted() from public, anon, authenticated;
revoke execute on function public.notify_driver_cash_reminder() from public, anon, authenticated;
revoke execute on function public.notify_driver_new_offer() from public, anon, authenticated;
revoke execute on function public.notify_merchant_new_order() from public, anon, authenticated;
revoke execute on function public.send_airport_ride_reminders() from public, anon, authenticated;
revoke execute on function public._award_loyalty_points() from public, anon, authenticated;
revoke execute on function public._guard_order_service_control() from public, anon, authenticated;
revoke execute on function public._guard_ride_service_control() from public, anon, authenticated;
revoke execute on function public.guard_store_order_pricing() from public, anon, authenticated;
