-- =====================================================================
--  وصّلها — Security #29: تأخير وصول السائق (خصم تلقائي) + مشوار متعدد النقاط
--
--  1) rides.arrived_at + دالة mark_ride_arrived: بدل ما التطبيق يعمل PATCH
--     مباشر على status بس (زي ما كان)، الدالة دي بتحسب وقت التأخير على
--     السيرفر (من accepted_at لحد وقت الوصول الفعلي) وتخصم 20 جنيه من
--     محفظة السائق تلقائيًا لو اتأخر أكتر من 5 دقايق — بنفس منطق الثقة
--     السيرفر-فقط اللي settle_ride_commission شغال بيه (العميل/التطبيق
--     مايقدرش يزوّر وقت الوصول لأنه بيتسجل وقت التنفيذ نفسه).
--
--  2) rides.stops (jsonb): نقاط توقف وسيطة للمشوار متعدد النقاط (نقطة
--     الانطلاق تفضل from_area/from_lat/from_lng، والوجهة النهائية تفضل
--     to_area/to_lat/to_lng زي ما هي — العمود ده بس للنقاط الوسيطة بينهم،
--     زي [{"name":"...","lat":...,"lng":...}, ...]). مفيش تغيير مطلوب في
--     guard_ride_fare() — الأجرة أصلاً بتتحسب من distance_km الإجمالي
--     (اللي التطبيق هيبعته كمجموع كل الأرجل) + to_area (الوجهة النهائية)
--     بالظبط زي رحلة عادية، فالمشوار متعدد النقاط بيتحاسب صح من غير أي
--     تعديل في التريجر.
--
--  آمن لإعادة التشغيل. شغّله كامل مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) أعمدة جديدة
-- ---------------------------------------------------------------------
alter table public.rides add column if not exists arrived_at timestamptz;
alter table public.rides add column if not exists stops jsonb default '[]'::jsonb;

-- ---------------------------------------------------------------------
-- 2) mark_ride_arrived — يسجّل وقت الوصول + خصم تأخير تلقائي لو لزم
-- ---------------------------------------------------------------------
create or replace function public.mark_ride_arrived(
  p_ride_id      text,
  p_driver_phone text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ride        record;
  v_late_minutes int;
  v_fee_applied  boolean := false;
begin
  select * into v_ride from public.rides where id::text = p_ride_id for update;
  if not found then
    raise exception 'ride_not_found';
  end if;
  if v_ride.driver_phone is distinct from p_driver_phone then
    raise exception 'not_your_ride';
  end if;
  if v_ride.arrived_at is not null then
    -- already marked — idempotent no-op, no double charge
    return jsonb_build_object('late_minutes', 0, 'fee_applied', false);
  end if;

  v_late_minutes := case
    when v_ride.accepted_at is null then 0
    else greatest(0, floor(extract(epoch from (now() - v_ride.accepted_at)) / 60))::int
  end;

  update public.rides set status = 'arrived', arrived_at = now() where id::text = p_ride_id;

  if v_late_minutes > 5 then
    v_fee_applied := true;
    perform public.add_wallet_balance(p_driver_phone, -20);
    insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
    values (
      'wtx-late-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
      p_driver_phone, -20, 'penalty', p_ride_id,
      'خصم تأخير وصول (' || v_late_minutes || ' دقيقة)', now()
    );
  end if;

  return jsonb_build_object('late_minutes', v_late_minutes, 'fee_applied', v_fee_applied);
end;
$$;

grant execute on function public.mark_ride_arrived(text, text) to anon, authenticated;
