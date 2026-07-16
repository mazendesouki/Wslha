-- =====================================================================
--  وصّلها — الأمان #7: تفعيل RLS على كل الجداول المكشوفة + سد 3 ثغرات حقيقية
--
--  ⚠️ السياق: النظام يستخدم مصادقة مخصّصة بالتليفون/الباسورد (لا يوجد
--  Supabase Auth ولا auth.uid()) — كل الصفحات تستخدم نفس مفتاح anon
--  المباشر. لذلك RLS هنا لا يقدر يميّز "صاحب الصف" فعليًا لمعظم الجداول؛
--  دوره الأساسي: (أ) توثيق/تثبيت الوصول الحالي بشكل صريح، (ب) قفل
--  الكتابة المباشرة على العمليات الحسّاسة وتحويلها لدوال RPC محمية
--  (نفس النمط المطبّق قبل كده على accounts وwallets).
--
--  الأجزاء:
--  1) تفعيل RLS + سياسات تحافظ على كل الاستخدام الحالي شغّال (rides,
--     orders, stores, driver_locations, driver_applications,
--     merchant_applications, accounts) — بلا كسر أي صفحة.
--  2) admin_logs: قفل كامل (مش مستخدم في الكود إطلاقًا حاليًا).
--  3) wallet_transactions: منع POST مباشر، وربطه بدالة log_wallet_transaction().
--  4) stores.rating/reviews: منع UPDATE مباشر على العمودين، وربطه بدالة
--     update_store_rating() — باقي أعمدة المتجر (is_open، البيانات...)
--     تفضل قابلة للتعديل المباشر من التاجر زي ما هي.
--  5) orders: دالة lookup_order_by_code() تُرجع فقط الحقول اللازمة للتتبع
--     العام (مش الصف كامل) — القراءة المباشرة بالكود تفضل شغالة (تتبع
--     بدون تسجيل دخول باختيارك)، الدالة دي تقليل تسرّب حقول حسّاسة إضافية.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- =====================================================================
-- 1) تفعيل RLS + سياسات تحافظ على كل استخدام حالي (Tier 1)
-- =====================================================================

-- ── accounts ── (SELECT ممنوع أصلاً من الأمان #6 — هنا فقط نفعّل RLS
--    رسميًا ونثبّت INSERT/UPDATE/DELETE بنفس الوضع الحالي)
alter table public.accounts enable row level security;
drop policy if exists accounts_insert_all on public.accounts;
create policy accounts_insert_all on public.accounts for insert to anon, authenticated with check (true);
drop policy if exists accounts_update_all on public.accounts;
create policy accounts_update_all on public.accounts for update to anon, authenticated using (true) with check (true);
drop policy if exists accounts_delete_all on public.accounts;
create policy accounts_delete_all on public.accounts for delete to anon, authenticated using (true);
-- ملاحظة: مفيش سياسة SELECT — القراءة المباشرة تفضل ممنوعة (لازم عبر lookup_account/admin_list_accounts).

-- ── rides ──
alter table public.rides enable row level security;
drop policy if exists rides_select_all on public.rides;
create policy rides_select_all on public.rides for select to anon, authenticated using (true);
drop policy if exists rides_insert_all on public.rides;
create policy rides_insert_all on public.rides for insert to anon, authenticated with check (true);
drop policy if exists rides_update_all on public.rides;
create policy rides_update_all on public.rides for update to anon, authenticated using (true) with check (true);
drop policy if exists rides_delete_all on public.rides;
create policy rides_delete_all on public.rides for delete to anon, authenticated using (true);

-- ── orders ──
alter table public.orders enable row level security;
drop policy if exists orders_select_all on public.orders;
create policy orders_select_all on public.orders for select to anon, authenticated using (true);
drop policy if exists orders_insert_all on public.orders;
create policy orders_insert_all on public.orders for insert to anon, authenticated with check (true);
drop policy if exists orders_update_all on public.orders;
create policy orders_update_all on public.orders for update to anon, authenticated using (true) with check (true);
drop policy if exists orders_delete_all on public.orders;
create policy orders_delete_all on public.orders for delete to anon, authenticated using (true);

-- ── stores ── (SELECT/DELETE مفتوحين زي ما هما؛ UPDATE مفتوح لكن سنمنع
--    عمودي rating/reviews تحديدًا في القسم 4 تحت)
alter table public.stores enable row level security;
drop policy if exists stores_select_all on public.stores;
create policy stores_select_all on public.stores for select to anon, authenticated using (true);
drop policy if exists stores_update_all on public.stores;
create policy stores_update_all on public.stores for update to anon, authenticated using (true) with check (true);
drop policy if exists stores_delete_all on public.stores;
create policy stores_delete_all on public.stores for delete to anon, authenticated using (true);
-- ملاحظة: مفيش سياسة INSERT — مفيش أي صفحة بتعمل INSERT مباشر لجدول stores
-- حاليًا في الكود، فتفعيل RLS بيقفلها تلقائيًا كإجراء احترازي إضافي.

-- ── driver_locations ── (يفضل مفتوح للقراءة عشان Realtime + polling يشتغلوا
--    زي ما هما — قرار مقصود، مش سهو؛ راجع التعليق أعلى الملف)
alter table public.driver_locations enable row level security;
drop policy if exists driver_locations_select_all on public.driver_locations;
create policy driver_locations_select_all on public.driver_locations for select to anon, authenticated using (true);
drop policy if exists driver_locations_upsert_all on public.driver_locations;
create policy driver_locations_upsert_all on public.driver_locations for insert to anon, authenticated with check (true);
drop policy if exists driver_locations_update_all on public.driver_locations;
create policy driver_locations_update_all on public.driver_locations for update to anon, authenticated using (true) with check (true);
drop policy if exists driver_locations_delete_all on public.driver_locations;
create policy driver_locations_delete_all on public.driver_locations for delete to anon, authenticated using (true);

-- ── driver_applications ── (نفس نمط الوصول الحالي بالكامل)
alter table public.driver_applications enable row level security;
drop policy if exists driver_apps_select_all on public.driver_applications;
create policy driver_apps_select_all on public.driver_applications for select to anon, authenticated using (true);
drop policy if exists driver_apps_insert_all on public.driver_applications;
create policy driver_apps_insert_all on public.driver_applications for insert to anon, authenticated with check (true);
drop policy if exists driver_apps_update_all on public.driver_applications;
create policy driver_apps_update_all on public.driver_applications for update to anon, authenticated using (true) with check (true);
drop policy if exists driver_apps_delete_all on public.driver_applications;
create policy driver_apps_delete_all on public.driver_applications for delete to anon, authenticated using (true);

-- ── merchant_applications ──
alter table public.merchant_applications enable row level security;
drop policy if exists merchant_apps_select_all on public.merchant_applications;
create policy merchant_apps_select_all on public.merchant_applications for select to anon, authenticated using (true);
drop policy if exists merchant_apps_insert_all on public.merchant_applications;
create policy merchant_apps_insert_all on public.merchant_applications for insert to anon, authenticated with check (true);
drop policy if exists merchant_apps_update_all on public.merchant_applications;
create policy merchant_apps_update_all on public.merchant_applications for update to anon, authenticated using (true) with check (true);
drop policy if exists merchant_apps_delete_all on public.merchant_applications;
create policy merchant_apps_delete_all on public.merchant_applications for delete to anon, authenticated using (true);

-- =====================================================================
-- 2) admin_logs — قفل كامل (مش مستخدم في أي صفحة بالكود حاليًا)
-- =====================================================================
alter table public.admin_logs enable row level security;
-- عمدًا بلا أي policy → anon/authenticated يتقفلوا تمامًا؛ service_role بس
-- (اللي بيتجاوز RLS دايمًا) يقدر يوصل، مناسب لو حابب تستخدمه من دوال إدارية لاحقًا.
revoke all on public.admin_logs from anon, authenticated;

-- =====================================================================
-- 3) wallet_transactions — منع الكتابة المباشرة، وربطها بدالة محمية
-- =====================================================================
alter table public.wallet_transactions enable row level security;
drop policy if exists wallet_tx_select_all on public.wallet_transactions;
create policy wallet_tx_select_all on public.wallet_transactions for select to anon, authenticated using (true);
drop policy if exists wallet_tx_delete_all on public.wallet_transactions;
create policy wallet_tx_delete_all on public.wallet_transactions for delete to anon, authenticated using (true);
-- ملاحظة: مفيش سياسة insert/update → القراءة والحذف (لتنظيف الحساب من
-- الأدمن) يفضلوا شغالين، لكن الإضافة/التعديل المباشر بقى ممنوع تمامًا.
revoke insert, update on public.wallet_transactions from anon, authenticated;

create or replace function public.log_wallet_transaction(
  p_phone        text,
  p_amount       numeric,
  p_type         text,
  p_id           text default null,
  p_reference_id text default null,
  p_note         text default null
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_phone is null or length(trim(p_phone)) = 0 then
    raise exception 'رقم الهاتف مطلوب';
  end if;
  if p_amount is null or p_amount = 0 then
    raise exception 'المبلغ غير صالح';
  end if;
  if p_type not in ('earning','commission','admin_credit','admin_debit','withdrawal','deposit','transfer_in','transfer_out') then
    raise exception 'نوع معاملة غير معروف: %', p_type;
  end if;

  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (coalesce(p_id, 'wtx-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6)),
          p_phone, p_amount, p_type, p_reference_id, p_note, now());
end;
$$;

grant execute on function public.log_wallet_transaction(text, numeric, text, text, text, text) to anon, authenticated;

-- =====================================================================
-- 4) stores.rating/reviews — منع التعديل المباشر على العمودين، دالة بدلاً منه
-- =====================================================================
revoke update (rating, reviews) on public.stores from anon, authenticated;

create or replace function public.update_store_rating(p_store_id text, p_new_rating int)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old_rating  numeric;
  v_old_count   int;
  v_new_count   int;
  v_new_rating  numeric;
begin
  if p_new_rating is null or p_new_rating < 1 or p_new_rating > 5 then
    raise exception 'التقييم لازم يكون رقم من 1 إلى 5';
  end if;

  select rating, reviews into v_old_rating, v_old_count from public.stores where id = p_store_id for update;
  if not found then
    raise exception 'المتجر غير موجود';
  end if;

  v_old_count  := coalesce(v_old_count, 0);
  v_new_count  := v_old_count + 1;
  -- متوسط تراكمي: ((المتوسط القديم × عدد التقييمات القديم) + التقييم الجديد) ÷ العدد الجديد
  v_new_rating := (coalesce(v_old_rating, 5) * v_old_count + p_new_rating) / v_new_count;

  update public.stores
     set rating = round(v_new_rating::numeric, 2), reviews = v_new_count
   where id = p_store_id;
end;
$$;

grant execute on function public.update_store_rating(text, int) to anon, authenticated;

-- =====================================================================
-- 5) orders — دالة تتبّع عامة بحقول محدودة (بدون تسجيل دخول، بالكود فقط)
-- =====================================================================
create or replace function public.lookup_order_by_code(p_code text)
returns table (
  id uuid, code text, status text, store_name text, store_emoji text, store_id text,
  driver_phone text, driver_name text, address text, area text,
  items_summary text, subtotal numeric, delivery_fee numeric, total numeric, payment text,
  store_lat double precision, store_lng double precision,
  customer_lat double precision, customer_lng double precision,
  accepted_at timestamptz, ready_at timestamptz, picked_up_at timestamptz, delivered_at timestamptz,
  created_at timestamptz
)
language sql
security definer
set search_path = public, extensions
stable
as $$
  select id, code, status, store_name, store_emoji, store_id,
         driver_phone, driver_name, address, area,
         items_summary, subtotal, delivery_fee, total, payment,
         store_lat, store_lng, customer_lat, customer_lng,
         accepted_at, ready_at, picked_up_at, delivered_at, created_at
    from public.orders
   where code = p_code
   limit 1;
$$;

grant execute on function public.lookup_order_by_code(text) to anon, authenticated;
