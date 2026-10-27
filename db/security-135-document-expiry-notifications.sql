-- =====================================================================
--  وصّلها — Security #135: إشعارات انتهاء صلاحية مستندات السائق
--
--  بند 7 من "خدمات المركبات" — إشعار السائق (وإدراجه في notifications
--  اللي بيشوفها الأدمن كمان) قبل ما مستنداته (الرخصة، رخصة العربية،
--  التأمين، الفحص، البطاقة) تنتهي. المستندات وتواريخ انتهائها موجودة
--  أصلًا في driver_applications من التسجيل (security-??) — مفيش
--  داعي لمستندات جديدة.
--
--  بتتفحص 5 نقاط زمنية قبل الانتهاء (30/14/7/3/1 يوم) + يوم الانتهاء
--  نفسه (0) — وبتستخدم نفس مسار send-push الموجود (بيسجل في
--  notifications تلقائيًا لكل مستلم، زي باقي التذكيرات في المشروع).
--  الـ tag بيتضمن تاريخ الانتهاء بالظبط، فحتى لو الـ cron اشتغل أكتر
--  من مرة في نفس اليوم (أو السائق جدد المستند لاحقًا بتاريخ مختلف)،
--  الإشعار بيتبعت مرة واحدة بس لكل (مستند × نقطة زمنية × تاريخ انتهاء).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.check_document_expiry_notifications()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_driver record;
  v_doc record;
  v_days_left int;
  v_tag text;
  v_label text;
  v_milestones int[] := array[30, 14, 7, 3, 1, 0];
begin
  for v_driver in
    select phone::text as phone, full_name,
           national_id_expiry, license_expiry, vehicle_reg_expiry, insurance_expiry, inspection_expiry
      from public.driver_applications
     where status = 'approved'
  loop
    for v_doc in
      select * from (values
        ('national_id_number', v_driver.national_id_expiry, 'البطاقة الشخصية'),
        ('license',            v_driver.license_expiry,     'رخصة القيادة'),
        ('vehicle_reg',        v_driver.vehicle_reg_expiry,  'رخصة العربية'),
        ('insurance',          v_driver.insurance_expiry,    'التأمين'),
        ('inspection',         v_driver.inspection_expiry,   'الفحص الدوري')
      ) as docs(doc_key, expiry, label)
    loop
      if v_doc.expiry is null then continue; end if;
      v_days_left := v_doc.expiry - current_date;
      if v_days_left <> all(v_milestones) then continue; end if;

      v_label := v_doc.label;
      v_tag := 'wslha-doc-expiry-' || v_driver.phone || '-' || v_doc.doc_key || '-' || v_doc.expiry::text || '-' || v_days_left::text;

      -- Already sent this exact (doc × milestone × expiry date) combo.
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
          'title', case when v_days_left <= 0 then '⚠️ مستند منتهي الصلاحية' else '⏰ مستند قربت تنتهي صلاحيته' end,
          'body',  case
                      when v_days_left <= 0 then v_label || ' انتهت صلاحيتها — جدّدها علشان تقدر تكمل شغل عادي'
                      else v_label || ' هتنتهي صلاحيتها خلال ' || v_days_left::text || ' يوم — جدّدها قبل ما تنتهي'
                    end,
          'url',   '/driver-dashboard',
          'tag',   v_tag
        )
      );
    end loop;
  end loop;
end;
$$;

-- يشتغل مرة واحدة يوميًا (الساعة 8 صباحًا بتوقيت UTC).
select cron.unschedule(jobid) from cron.job where jobname = 'check-document-expiry';
select cron.schedule('check-document-expiry', '0 8 * * *', $$select public.check_document_expiry_notifications();$$);
