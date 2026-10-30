-- =====================================================================
--  وصّلها — Security #143: تذكير بالصيانة الدورية المتأخرة/القريبة
--  (Push تلقائي للسائق)
--
--  security-142 بنى تتبّع "صيانة مطلوبة" (get_maintenance_due_status)،
--  لكنه كان pull-only — السائق ما يعرفش إن عنده عنصر متأخر إلا لو فتح
--  شاشة "خدمات المركبة" بنفسه. ده أول Workflow Automation للتطبيق فوق
--  الـ8 cron jobs الموجودين (رحلات مجدولة/متكررة، تذكير مطار، انتهاء
--  مستندات، تنبيه معدل الإلغاء، حملات تسويقية).
--
--  يشتغل يوميًا، ويبعت Push مرة واحدة فقط لكل (سائق × عنصر × حالة ×
--  آخر قراءة عداد مسجَّلة للعنصر ده) — نفس أسلوب الـ dedup بالـ tag في
--  notifications الموجود فعلاً (security-77/135)، فمفيش داعي لجدول
--  تتبّع إضافي:
--    - الـ tag بيتضمن last_done_odometer (أو 'none' لو لسه متعمل)،
--      مش current_odometer — عمدًا: current_odometer بيزيد مع أي سجل
--      وقود/كاوتش جديد (مش بس الصيانة نفسها)، فلو استخدمناه هيبعت
--      إشعار جديد كل مرة السائق يسجّل بنزين وهو لسه متأخر في عنصر
--      صيانة، وده أكتر من المطلوب (المطلوب: مرة واحدة لحد ما يعمل
--      الصيانة فعلاً).
--    - تغيّر الحالة (due_soon → overdue) بيعتبر "عبور" جديد فيبعت
--      تذكير جديد، مطابق لما اتفقنا عليه.
--    - لما السائق يسجّل الصيانة فعلاً، last_done_odometer بيتغيّر،
--      فالدورة الجاية (due_soon/overdue تاني) هتبعت تذكير جديد تلقائيًا
--      من غير أي reset يدوي.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.send_maintenance_due_reminders()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_driver record;
  v_item record;
  v_tag text;
begin
  for v_driver in
    select phone::text as phone from public.driver_applications where status = 'approved'
  loop
    for v_item in
      select * from public.get_maintenance_due_status(v_driver.phone)
       where status in ('due_soon', 'overdue')
    loop
      v_tag := 'wslha-maint-due-' || v_driver.phone || '-' || v_item.item_key || '-' || v_item.status
               || '-' || coalesce(v_item.last_done_odometer::text, 'none');

      -- Already notified for this exact (item × status × last-done
      -- baseline) combo — see doc comment above for why the baseline,
      -- not the ever-climbing current odometer, anchors the dedup.
      if exists (select 1 from public.notifications where phone = v_driver.phone and tag = v_tag) then
        continue;
      end if;

      perform net.http_post(
        url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'x-push-secret', public._push_trigger_secret(),
          'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
        ),
        body    := jsonb_build_object(
          'phone', v_driver.phone,
          'title', case when v_item.status = 'overdue' then '⛔ صيانة متأخرة' else '⏰ صيانة قربت تستحق' end,
          'body',  case
                      when v_item.status = 'overdue'
                        then v_item.label_ar || ' متأخرة — ' || coalesce(v_item.km_since::text, '0') || ' كم فوق الموعد'
                      else v_item.label_ar || ' قربت تستحق — سجّلها لما تخلّصها'
                    end,
          'url',   '/driver-dashboard',
          'tag',   v_tag
        )
      );
    end loop;
  end loop;
end;
$$;

-- يشتغل مرة واحدة يوميًا (الساعة 9 صباحًا بتوقيت UTC — بعد check-document-expiry بساعة).
select cron.unschedule(jobid) from cron.job where jobname = 'send-maintenance-due-reminders';
select cron.schedule('send-maintenance-due-reminders', '0 9 * * *', $$select public.send_maintenance_due_reminders();$$);
