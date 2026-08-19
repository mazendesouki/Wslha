-- =====================================================================
--  وصّلها — Security #26: قفل سياسات RLS قديمة كانت لسه شغالة بالخطأ
--
--  supabase-rls-policies.sql (من مرحلة مبكرة في المشروع) عمل سياسات
--  "FOR ALL USING (true)" على ratings و push_subscriptions و wallets —
--  وبعدها ملفات لاحقة (pushnotifications.sql، security-07، إلخ) عرّفت
--  سياسات أضيق بأسماء مختلفة، لكن محدش عمل DROP للسياسة القديمة الواسعة.
--  في Postgres RLS، كل السياسات على نفس الجدول بتتجمع بـ OR — يعني وجود
--  سياسة واحدة قديمة "مفتوحة للكل" كفاية إنها تلغي أي تضييق لاحق. النتيجة:
--
--   • ratings: أي حد (من غير أي علاقة بالتقييم) يقدر يعمل UPDATE لأي عمود
--     في أي صف تقييم (يغيّر رقم التقييم نفسه، التعليق، رقم الهاتف...) أو
--     DELETE لأي تقييم — رغم إن الاستخدام الشرعي الوحيد للـ UPDATE هو رد
--     السائق على تقييم عميل له (driver_reply)، ومفيش استخدام شرعي لـ DELETE
--     خالص.
--   • push_subscriptions: كان القصد (موثّق في pushnotifications.sql) إن
--     محتوى الاشتراكات (endpoints) ميتقراش من العميل خالص — بس السياسة
--     القديمة كانت بتسمح بالقراءة برضه.
--   • wallet_transactions: DELETE كان مفتوح للكل من غير أي تحقق (حتى لو
--     القصد كان "تنظيف من الأدمن" — مفيش تحقق أدمن فعلي في السياسة).
--
--  الملف ده يقفل الثغرات دي فقط، من غير ما يغيّر أي سلوك شرعي حالي —
--  اتأكدت (grep) إن مفيش أي صفحة في الموقع أو التطبيق بتعمل DELETE مباشر
--  على wallet_transactions، وإن استخدام UPDATE على ratings محصور في رد
--  السائق (driver-dashboard.astro sendReply()) اللي دلوقتي بيتحول لدالة
--  RPC محمية بدل الـ PATCH المباشر.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- =====================================================================
-- 1) ratings — قفل UPDATE/DELETE المباشرين، إبقاء SELECT/INSERT زي ما هما
-- =====================================================================
drop policy if exists "allow_anon_all_ratings" on public.ratings;

drop policy if exists ratings_select_all on public.ratings;
create policy ratings_select_all on public.ratings
  for select to anon, authenticated using (true);

drop policy if exists ratings_insert_all on public.ratings;
create policy ratings_insert_all on public.ratings
  for insert to anon, authenticated with check (true);

-- عمدًا بلا سياسة update/delete → ممنوعين تمامًا لـ anon/authenticated؛
-- رد السائق بقى عن طريق الدالة المحمية تحت بس.

create or replace function public.submit_driver_reply(
  p_rating_id    uuid,
  p_driver_phone text,
  p_reply        text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_reply is null or length(trim(p_reply)) = 0 then
    raise exception 'الرد لا يمكن أن يكون فارغًا';
  end if;

  update public.ratings
     set driver_reply = p_reply
   where id = p_rating_id
     and driver_phone = p_driver_phone;

  if not found then
    raise exception 'التقييم غير موجود أو لا يخصك';
  end if;
end;
$$;

grant execute on function public.submit_driver_reply(uuid, text, text) to anon, authenticated;

-- =====================================================================
-- 2) push_subscriptions — قفل السياسة القديمة اللي كانت بتسمح بالـ SELECT
-- =====================================================================
drop policy if exists "allow_anon_all_push_subs" on public.push_subscriptions;
-- السياسات الأضيق (push_subs_insert_own/update_own/delete_own) من
-- pushnotifications.sql تفضل شغالة زي ما هي — القراءة تفضل ممنوعة لـ
-- anon/authenticated زي ما كان مقصود من الأول.

-- =====================================================================
-- 3) wallet_transactions — قفل DELETE المباشر (مفيش استخدام شرعي له)
-- =====================================================================
drop policy if exists wallet_tx_delete_all on public.wallet_transactions;
revoke delete on public.wallet_transactions from anon, authenticated;
