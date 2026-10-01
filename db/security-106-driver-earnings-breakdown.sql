-- =====================================================================
--  وصّلها — Security #106: تقرير أرباح أسبوعي/شهري للسائق
--
--  get_driver_trip_stats (security-17/28) بيرجّع إجمالي حياة السائق بس
--  (رقم واحد كبير) — مفيش أي تقسيم بالفترة. get_driver_progress
--  (security-71) بيرجّع عدد رحلات اليوم/الأسبوع بس (مش المبلغ).
--
--  الحل: دالة جديدة بترجع صفوف مجمّعة بالأسبوع أو الشهر، مبنية مباشرة
--  على wallet_transactions (type='earning') — نفس مصدر الحقيقة اللي كل
--  حسابات الأرباح التانية في المشروع بتستخدمه (مش إعادة حساب fare×rate)،
--  وده أبسط كمان من الرجوع لـ rides/orders لأن تاريخ "الكسب" الحقيقي هو
--  تاريخ قيد wallet_transactions نفسه.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.get_driver_earnings_breakdown(
  p_driver_phone text, p_period text default 'week', p_periods int default 8
) returns table(period_start timestamptz, trips bigint, total_earnings numeric)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_local text;
  v_intl  text;
  v_unit  text;
  v_n     int;
begin
  if p_driver_phone is null or length(trim(p_driver_phone)) = 0 then
    raise exception 'driver_phone_required';
  end if;

  v_unit := case when p_period = 'month' then 'month' else 'week' end;
  v_n    := greatest(coalesce(p_periods, 8), 1);
  v_local := case when p_driver_phone like '+20%' then '0'||substr(p_driver_phone,4) else p_driver_phone end;
  v_intl  := case when p_driver_phone like '0%'   then '+2'||p_driver_phone           else p_driver_phone end;

  return query
    select date_trunc(v_unit, wt.created_at) as period_start,
           count(distinct wt.reference_id) as trips,
           coalesce(sum(wt.amount), 0) as total_earnings
      from public.wallet_transactions wt
     where wt.phone in (v_local, v_intl)
       and wt.type = 'earning'
       and wt.created_at >= date_trunc(v_unit, now())
                             - (v_n - 1) * (case when v_unit = 'month' then interval '1 month' else interval '1 week' end)
     group by 1
     order by 1 desc;
end;
$$;
grant execute on function public.get_driver_earnings_breakdown(text, text, int) to anon, authenticated;
