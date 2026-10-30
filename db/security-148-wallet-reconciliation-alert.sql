-- =====================================================================
--  وصّلها — Security #148: مطابقة يومية لرصيد المحفظة مع دفتر الحركات
--
--  رابع أتمتة (Workflow Automation) — نفس نمط security-104/145/146.
--  security-147 صحّح باگ حقيقي اتكشف وقت بناء الأتمتة دي بالظبط: رصيد
--  محفظة 'platform' كان بعيد عن مجموع wallet_transactions بتاعته بـ
--  4468 ج.م، من غير ما يلاحظه أي حد لحد ما اتشغّلت مطابقة فعلية على
--  الداتا الحية. الأتمتة دي تضمن إن أي فجوة جديدة (زي دي، أو أي باگ/
--  تلاعب مستقبلي) تتكشف تلقائيًا بدل الاعتماد على مراجعة يدوية بالصدفة.
--
--  يشتغل يوميًا، ولكل phone عنده صف في wallets، بيقارن balance بمجموع
--  wallet_transactions.amount بتاعته. لو الفرق أكبر من هامش صغير
--  (قرش واحد، لتفادي أخطاء التقريب)، بيسجّل admin_alert (نفس جدول/نمط
--  security-104/145) بكولداون لكل رقم على حدة (24 ساعة) عشان ما يكررش
--  نفس التنبيه كل يوم طول ما الفجوة لسه موجودة من غير حل.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value) values
  ('alert_wallet_mismatch_enabled', 'true'),
  ('alert_wallet_mismatch_min_diff', '1'),
  ('alert_wallet_mismatch_cooldown_hours', '24')
on conflict (key) do nothing;

create or replace function public.check_wallet_reconciliation()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_enabled   boolean;
  v_min_diff  numeric;
  v_cooldown  int;
  v_row       record;
begin
  v_enabled  := coalesce((select value from public.app_settings where key = 'alert_wallet_mismatch_enabled'), 'true') = 'true';
  if not v_enabled then return; end if;

  v_min_diff := coalesce((select value::numeric from public.app_settings where key = 'alert_wallet_mismatch_min_diff'), 1);
  v_cooldown := coalesce((select value::int     from public.app_settings where key = 'alert_wallet_mismatch_cooldown_hours'), 24);

  for v_row in
    select w.phone, w.balance, coalesce(t.sum_amount, 0) as tx_sum,
           w.balance - coalesce(t.sum_amount, 0) as diff
      from public.wallets w
      left join (
        select phone, sum(amount) as sum_amount from public.wallet_transactions group by phone
      ) t on t.phone = w.phone
     where abs(w.balance - coalesce(t.sum_amount, 0)) >= v_min_diff
  loop
    if exists (
      select 1 from public.admin_alerts
       where reference_type = 'wallet_mismatch' and reference_id = v_row.phone
         and created_at > now() - (v_cooldown || ' hours')::interval
    ) then
      continue;
    end if;

    insert into public.admin_alerts (alert_type, message, metric_value, threshold, reference_type, reference_id)
    values (
      'wallet_mismatch',
      'عدم تطابق محفظة ' || v_row.phone || ': الرصيد ' || v_row.balance || ' ج.م، دفتر الحركات ' || v_row.tx_sum
        || ' ج.م (فرق ' || v_row.diff || ' ج.م)',
      v_row.diff, v_min_diff, 'wallet_mismatch', v_row.phone
    );

    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type','application/json','x-push-secret', public._push_trigger_secret(),
                                     'apikey','sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'),
      body    := jsonb_build_object('target','admin','title','⚠️ عدم تطابق محفظة',
                                     'body', 'محفظة ' || v_row.phone || ' فيها فرق ' || v_row.diff || ' ج.م — راجع لوحة التحكم', 'url','/admin')
    );
  end loop;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'check-wallet-reconciliation';
select cron.schedule('check-wallet-reconciliation', '0 11 * * *', $$select public.check_wallet_reconciliation();$$);
