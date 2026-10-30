-- =====================================================================
--  وصّلها — Security #146: تصعيد تلقائي لتذكيرات سداد الكاش
--
--  security-92 بنى "تذكير سداد الكاش": الأدمن يسجّل مبلغ مستحق، السائق
--  ياخد Push واحد لحظة الإنشاء بس، وبعد كده التذكير يفضل معلّق (نافذة
--  في التطبيق) لحد ما الأدمن يعلّمه "اتسدد" يدويًا — من غير أي نظام
--  يتابع أو يصعّد لو السائق اتجاهل التذكير وفات due_at (7 أيام افتراضيًا).
--
--  الحل: Cron يومي (نفس تردد check-document-expiry) بيفحص كل التذكيرات
--  النشطة (not settled) ويبعت:
--    1) تذكير Push للسائق بنفسه في نقاط زمنية محددة (باقي يومين/يوم
--       واحد/يوم الاستحقاق، وبعدين وهو متأخر: يوم/3 أيام/أسبوع/أسبوعين)
--       — نفس أسلوب الـ milestones في security-135 (تذكير انتهاء
--       المستندات)، بالضبط بنفس الـ tag-dedup عشان ما يتكررش.
--    2) تنبيه للأدمن (admin_alerts، نفس جدول/نمط security-104/145) لو
--       التذكير فات عليه 3 أيام فأكتر من غير سداد — عشان الأدمن يتابع
--       بنفسه (مفيش أي خصم أوتوماتيكي من المحفظة أو تعليق حساب هنا —
--       ده قرار سياسة أكبر محتاج موافقة صريحة، مش جزء من الأتمتة دي).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.escalate_cash_reminders()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_reminder          record;
  v_days_left         int;
  v_days_overdue      int;
  v_tag               text;
  v_admin_cooldown_h  int := 24;
  v_admin_min_overdue int := 3;
  v_before_milestones int[] := array[2, 1, 0];
  v_overdue_milestones int[] := array[1, 3, 7, 14];
begin
  for v_reminder in
    select * from public.driver_cash_reminders where not settled
  loop
    v_days_left := (v_reminder.due_at::date - current_date);

    if v_days_left = any(v_before_milestones) then
      v_tag := 'wslha-cash-reminder-escalate-' || v_reminder.id || '-before-' || v_days_left::text;
      if not exists (select 1 from public.notifications where phone = v_reminder.driver_phone and tag = v_tag) then
        perform net.http_post(
          url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type','application/json','x-push-secret', public._push_trigger_secret(),
                                         'apikey','sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'),
          body    := jsonb_build_object(
            'phone', v_reminder.driver_phone,
            'title', '💰 تذكير سداد رصيد كاش',
            'body',  case
                       when v_days_left = 0 then 'النهاردة آخر يوم لسداد ' || v_reminder.amount || ' ج.م المستحقة'
                       else 'باقي ' || v_days_left::text || ' يوم على سداد ' || v_reminder.amount || ' ج.م المستحقة'
                     end,
            'url',   '/driver-dashboard', 'tag', v_tag, 'type', 'cash_reminder', 'channel', 'wslha_rides'
          )
        );
      end if;

    elsif v_days_left < 0 then
      v_days_overdue := -v_days_left;

      if v_days_overdue = any(v_overdue_milestones) then
        v_tag := 'wslha-cash-reminder-escalate-' || v_reminder.id || '-overdue-' || v_days_overdue::text;
        if not exists (select 1 from public.notifications where phone = v_reminder.driver_phone and tag = v_tag) then
          perform net.http_post(
            url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
            headers := jsonb_build_object('Content-Type','application/json','x-push-secret', public._push_trigger_secret(),
                                           'apikey','sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'),
            body    := jsonb_build_object(
              'phone', v_reminder.driver_phone,
              'title', '⚠️ رصيد كاش متأخر السداد',
              'body',  v_reminder.amount || ' ج.م متأخرة السداد من ' || v_days_overdue::text || ' يوم — برجاء السداد فورًا',
              'url',   '/driver-dashboard', 'tag', v_tag, 'type', 'cash_reminder', 'channel', 'wslha_rides'
            )
          );
        end if;
      end if;

      -- تصعيد للأدمن لو فات 3 أيام فأكتر، بكولداون 24 ساعة لكل تذكير
      -- على حدة (نفس أسلوب security-145's per-reference cooldown).
      if v_days_overdue >= v_admin_min_overdue then
        if not exists (
          select 1 from public.admin_alerts
           where reference_type = 'cash_reminder' and reference_id = v_reminder.id::text
             and created_at > now() - (v_admin_cooldown_h || ' hours')::interval
        ) then
          insert into public.admin_alerts (alert_type, message, metric_value, threshold, reference_type, reference_id)
          values (
            'cash_reminder_overdue',
            'تذكير سداد كاش متأخر ' || v_days_overdue::text || ' يوم — السائق ' || v_reminder.driver_phone
              || ' لسه مديون بـ ' || v_reminder.amount || ' ج.م',
            v_days_overdue, v_admin_min_overdue, 'cash_reminder', v_reminder.id::text
          );
          perform net.http_post(
            url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
            headers := jsonb_build_object('Content-Type','application/json','x-push-secret', public._push_trigger_secret(),
                                           'apikey','sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'),
            body    := jsonb_build_object('target','admin','title','⚠️ رصيد كاش متأخر',
                                           'body', 'سائق مديون بـ ' || v_reminder.amount || ' ج.م من ' || v_days_overdue::text || ' يوم', 'url','/admin')
          );
        end if;
      end if;
    end if;
  end loop;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'escalate-cash-reminders';
select cron.schedule('escalate-cash-reminders', '0 10 * * *', $$select public.escalate_cash_reminders();$$);
