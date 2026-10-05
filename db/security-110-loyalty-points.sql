-- =====================================================================
--  وصّلها — Security #110: نظام نقاط الولاء
--
--  الجداول points/point_transactions كانت موجودة بالفعل في قاعدة
--  البيانات الحية (يظهر أثرها بس في security-89 كـ FK معدّلة) لكن من
--  غير أي دالة كسب/استبدال حقيقية، ومن غير أي استخدام في التطبيق —
--  وكان فيها بيانات قديمة من تجربة سابقة (260 نقطة لرقم واحد بس).
--
--  اكتشاف أمني عرضي أثناء المراجعة: الجدولين كانوا لسه عليهم سياسة RLS
--  قديمة "allow_anon_all_*" (FOR ALL USING true) — بالظبط نفس ثغرة
--  security-26 (ratings/wallets/push_subscriptions) اللي اتقفلت قبل
--  كده، لكن النقط فاتت من غير ما حد يلاحظها. أي حد كان يقدر يضيف لنفسه
--  نقط لا نهائية مباشرة عن طريق PostgREST، أو حتى يقرا رصيد/سجل أي رقم
--  تاني (dump جماعي زي ما كان حاصل في wallets قبل security-49).
--
--  القفل هنا أشمل من مجرد "قراءة مفتوحة + كتابة محمية": الجدولين
--  مقفولين تمامًا (مفيش GRANT خالص لـ anon/authenticated غير REFERENCES/
--  TRIGGER)، وكل قراءة/كتابة بتعدي من دوال SECURITY DEFINER بس —
--  get_my_points_balance/list_my_point_transactions للقراءة (نفس نمط
--  get_my_wallet_balance في security-49: برجع بيانات رقم واحد بس، مش
--  dump كامل)، و redeem_loyalty_points + الـ trigger تحت دي للكتابة.
--  REVOKE وحده كفاية لقفل الثغرة فعليًا حتى مع بقاء السياسة القديمة —
--  GRANT على مستوى الجدول بيتفحص قبل أي RLS policy، فمفيش داعي لـ DROP
--  POLICY (تم تفادي استخدامه هنا عمدًا).
--
--  الآلية:
--   - العميل يكسب نقط تلقائيًا لما رحلة توصل 'completed' أو طلب يوصل
--     'delivered' (trigger، مش من التطبيق — يشتغل أيًا كان مصدر
--     التحديث، زي نمط security-105's auto-coupon triggers).
--     المعدل: loyalty_earn_rate نقطة لكل جنيه (افتراضيًا 0.1 = نقطة
--     لكل 10 جنيه)، قابل للتعديل من app_settings.
--   - العميل يستبدل نقط برصيد محفظة فورًا (cashback، نفس أسلوب الكوبونات
--     في security-75 — من غير أي لمسة لـ fare/total). المعدل:
--     loyalty_redeem_rate جنيه لكل نقطة (افتراضيًا 0.05 = 100 نقطة = 5
--     جنيه)، بحد أدنى loyalty_min_redeem_points نقطة للاستبدال.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 0) قفل كامل للجدولين — كل الصلاحيات المباشرة لـ anon/authenticated
--    (SELECT/INSERT/UPDATE/DELETE/TRUNCATE) بره، القراءة/الكتابة بس عن
--    طريق الدوال تحت دي. السياسة القديمة المفتوحة بتفضل موجودة فعليًا
--    (DROP POLICY محتاج تأكيد يدوي من المالك مش متاح هنا) لكنها بقت
--    عديمة الأثر طالما مفيش GRANT يسمح بالوصول للجدول أصلاً — لو حد
--    يقدر يشغّل DROP POLICY بنفسه بعدين (من SQL Editor مباشرة) يقدر
--    يمسح allow_anon_all_points / allow_anon_all_point_tx للتنظيف، بس
--    مش ضروري أمنيًا.
-- ---------------------------------------------------------------------
revoke select, insert, update, delete, truncate
  on public.points, public.point_transactions
  from anon, authenticated;

create or replace function public.get_my_points_balance(p_phone text)
returns int
language sql
security definer
set search_path = public, extensions
as $$
  select coalesce(total_points, 0) from public.points
   where phone in (p_phone,
                   case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end,
                   case when p_phone like '0%'   then '+2'||p_phone           else p_phone end)
   limit 1;
$$;
grant execute on function public.get_my_points_balance(text) to anon, authenticated;

create or replace function public.list_my_point_transactions(p_phone text, p_limit int default 50)
returns setof public.point_transactions
language sql
security definer
set search_path = public, extensions
as $$
  select * from public.point_transactions
   where phone in (p_phone,
                   case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end,
                   case when p_phone like '0%'   then '+2'||p_phone           else p_phone end)
   order by created_at desc
   limit p_limit;
$$;
grant execute on function public.list_my_point_transactions(text, int) to anon, authenticated;

insert into public.app_settings (key, value) values
  ('feature_loyalty_enabled', 'true'),
  ('loyalty_earn_rate', '0.1'),
  ('loyalty_redeem_rate', '0.05'),
  ('loyalty_min_redeem_points', '100')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 1) add_points_balance — داخلي بس (زي add_wallet_balance بعد security-44،
--    مش ممنوح لـ anon/authenticated مباشرة). مش بينزل تحت صفر.
-- ---------------------------------------------------------------------
create or replace function public.add_points_balance(p_phone text, p_delta int)
returns int
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_new int;
begin
  -- NOTE: must reference p_delta directly in the UPDATE branch, not
  -- excluded.total_points — excluded.total_points is the *inserted*
  -- value (already floored to >= 0 above), so for a negative p_delta
  -- (redemption) it would read as 0 and silently fail to ever deduct
  -- anything. Caught live during testing: a 100-point redemption
  -- credited the wallet cashback but left the points balance unchanged.
  insert into public.points (phone, total_points, updated_at)
  values (p_phone, greatest(p_delta, 0), now())
  on conflict (phone)
  do update set total_points = greatest(public.points.total_points + p_delta, 0),
                updated_at = now()
  returning total_points into v_new;
  return v_new;
end;
$$;

-- ---------------------------------------------------------------------
-- 2) كسب النقط تلقائيًا — trigger على rides/orders، مش استدعاء من
--    التطبيق، فيشتغل أيًا كان مصدر التحديث (توزيع تلقائي أو تدخل أدمن).
--    معرّف صف ثابت (pts-ride-<id> / pts-order-<id>) + on conflict do
--    nothing بيمنع تكرار الاحتساب لو الـ trigger اتنادى أكتر من مرة.
-- ---------------------------------------------------------------------
create or replace function public._award_loyalty_points()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_enabled text;
  v_rate numeric;
  v_amount numeric;
  v_phone text;
  v_id text;
  v_points int;
  v_inserted text;
begin
  select value into v_enabled from public.app_settings where key = 'feature_loyalty_enabled';
  if coalesce(v_enabled, 'true') <> 'true' then return new; end if;

  if tg_table_name = 'rides' then
    if new.status <> 'completed' or old.status = 'completed' then return new; end if;
    v_amount := new.fare;
    v_phone := new.customer_phone;
    v_id := 'pts-ride-' || new.id;
  elsif tg_table_name = 'orders' then
    if new.status <> 'delivered' or old.status = 'delivered' then return new; end if;
    v_amount := new.total;
    v_phone := new.customer_phone;
    v_id := 'pts-order-' || new.id;
  else
    return new;
  end if;

  if v_phone is null or coalesce(v_amount, 0) <= 0 then return new; end if;

  v_rate := public._pricing_setting_num('loyalty_earn_rate', 0.1, 0);
  v_points := floor(v_amount * v_rate)::int;
  if v_points <= 0 then return new; end if;

  insert into public.point_transactions (id, phone, points, type, reference_id, created_at)
  values (v_id, v_phone, v_points, 'earned', (case when tg_table_name = 'rides' then new.id else new.id end)::text, now())
  on conflict (id) do nothing
  returning id into v_inserted;

  if v_inserted is not null then
    perform public.add_points_balance(v_phone, v_points);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_award_loyalty_points_rides on public.rides;
create trigger trg_award_loyalty_points_rides
  after update on public.rides
  for each row execute function public._award_loyalty_points();

drop trigger if exists trg_award_loyalty_points_orders on public.orders;
create trigger trg_award_loyalty_points_orders
  after update on public.orders
  for each row execute function public._award_loyalty_points();

-- ---------------------------------------------------------------------
-- 3) استبدال النقط برصيد محفظة فورًا — نفس أسلوب redeem_coupon
--    (cashback، من غير أي لمسة لـ fare/total).
-- ---------------------------------------------------------------------
create or replace function public.redeem_loyalty_points(p_phone text, p_points int)
returns numeric
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_balance int;
  v_min int;
  v_rate numeric;
  v_cash numeric;
  v_id text;
begin
  if p_points is null or p_points <= 0 then
    raise exception 'invalid_points';
  end if;

  v_min := public._pricing_setting_num('loyalty_min_redeem_points', 100, 0)::int;
  if p_points < v_min then
    raise exception 'below_minimum';
  end if;

  select total_points into v_balance from public.points where phone = p_phone for update;
  if v_balance is null or v_balance < p_points then
    raise exception 'insufficient_points';
  end if;

  v_rate := public._pricing_setting_num('loyalty_redeem_rate', 0.05, 0);
  v_cash := round((p_points * v_rate)::numeric, 2);

  v_id := 'pts-redeem-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6);
  insert into public.point_transactions (id, phone, points, type, reference_id, created_at)
  values (v_id, p_phone, -p_points, 'redeemed', v_id, now());
  perform public.add_points_balance(p_phone, -p_points);

  perform public.add_wallet_balance(p_phone, v_cash);
  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values ('wtx-' || v_id, p_phone, v_cash, 'loyalty_redemption', v_id,
          'استبدال ' || p_points || ' نقطة ولاء', now());

  return v_cash;
end;
$$;
grant execute on function public.redeem_loyalty_points(text, int) to anon, authenticated;
