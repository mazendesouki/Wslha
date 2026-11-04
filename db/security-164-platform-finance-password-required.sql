-- =====================================================================
--  وصّلها — Security #164: تحصين get_platform_finance_summary و
--  get_platform_withdrawal_history بكلمة مرور المشرف (ثغرة حرجة)
--
--  اتكشفت أثناء اختبار حي بعد security-163: الدالتين دول كانوا بياخدوا
--  رقم تليفون المشرف بس (p_admin_phone) من غير أي كلمة مرور — وبيفحصوا
--  بس إن الرقم ده موجود كأدمن في accounts، من غير أي تحقق تاني. وهما
--  متاحين لـ anon (المفتاح العام المُضمَّن في كود الواجهة)، يعني أي حد
--  يعرف رقم تليفون المشرف (معلن وقابل للتخمين) يقدر ينادي الدالتين دول
--  مباشرة عبر REST API ويشوف:
--    - get_platform_finance_summary: إجمالي إيرادات المنصة، إجمالي
--      المسحوب، الرصيد المتاح، وتوزيعها على رحلات/توصيل/مطار.
--    - get_platform_withdrawal_history: آخر 200 عملية سحب (اسم الأدمن،
--      المبلغ، الرصيد قبل/بعد) — من غير أي كلمة مرور خالص.
--
--  الإصلاح: ضفنا p_admin_password وبقوا يستخدموا _check_admin()
--  المركزية (قفل 5 محاولات/15 دقيقة — security-159)، ورجعنا jsonb
--  {ok,...} بدل ما نعمل raise على فشل الدخول (علشان مفيش exception
--  يلغي أي insert محاولة فاشلة جوه _check_admin() — نفس الدرس من
--  security-158). لازم DROP FUNCTION الأول لأن التوقيع اتغيّر (باراميتر
--  جديد مطلوب + return type اتغيّر لـ jsonb).
--
--  العميل (admin.astro) اتعدّل ليبعت كلمة المرور المخزّنة مؤقتًا
--  (getAdminPass()) ويقرا result.ok.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

drop function if exists public.get_platform_finance_summary(text);
create or replace function public.get_platform_finance_summary(p_admin_phone text, p_admin_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_total_revenue numeric;
  v_total_withdrawn numeric;
  v_ride numeric; v_deliv numeric; v_air numeric;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials', 'message', 'كلمة مرور المشرف غير صحيحة أو محاولات كتير غلط');
  end if;

  select coalesce(sum(amount), 0) into v_total_revenue
    from public.wallet_transactions where phone = 'platform' and type = 'commission';
  select coalesce(sum(-amount), 0) into v_total_withdrawn
    from public.wallet_transactions where phone = 'platform' and type = 'withdrawal';

  select coalesce(sum(wt.amount), 0) into v_ride
    from public.wallet_transactions wt
    join public.rides r on r.id::text = wt.reference_id
   where wt.phone = 'platform' and wt.type = 'commission'
     and coalesce(r.ride_type, 'local') <> 'airport';

  select coalesce(sum(wt.amount), 0) into v_air
    from public.wallet_transactions wt
    join public.rides r on r.id::text = wt.reference_id
   where wt.phone = 'platform' and wt.type = 'commission'
     and r.ride_type = 'airport';

  select coalesce(sum(wt.amount), 0) into v_deliv
    from public.wallet_transactions wt
    join public.orders o on o.id::text = wt.reference_id
   where wt.phone = 'platform' and wt.type = 'commission';

  return jsonb_build_object(
    'ok', true,
    'total_revenue',   v_total_revenue,
    'total_withdrawn', v_total_withdrawn,
    'balance',          v_total_revenue - v_total_withdrawn,
    'by_type', jsonb_build_object('ride', v_ride, 'delivery', v_deliv, 'airport', v_air)
  );
end;
$$;
grant execute on function public.get_platform_finance_summary(text, text) to anon, authenticated;

drop function if exists public.get_platform_withdrawal_history(text);
create or replace function public.get_platform_withdrawal_history(p_admin_phone text, p_admin_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials', 'message', 'كلمة مرور المشرف غير صحيحة أو محاولات كتير غلط');
  end if;

  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_rows
    from (select * from public.platform_withdrawals order by created_at desc limit 200) t;

  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;
grant execute on function public.get_platform_withdrawal_history(text, text) to anon, authenticated;
