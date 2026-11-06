-- =====================================================================
--  وصّلها — Security #171: المرحلة الأولى من إصلاح جداول orders/rides/
--  stores المفتوحة بالكامل — تأمين الكتابة على stores
--
--  اتكشف إن جدول stores عنده RLS policies مفتوحة بالكامل (qual=true
--  على كل العمليات لـ anon) — يعني أي حد يقدر يعدّل أو يمسح أي متجر
--  مباشرة عبر الـ API، من غير أي تحقق هوية خالص، من غير حتى المرور
--  بالموقع. نفس المشكلة موجودة في orders و rides (شغل منفصل لاحق).
--
--  مهم: الـ INSERT فضل مفتوح عمدًا — تسجيل متجر جديد (merchant-dashboard
--  .astro) بيعمل insert مباشر بـ owner_phone بتاعه، وده سلوك متوقع/آمن
--  (مفيش بيانات موجودة ممكن تتبهدل، أسوأ حالة إنشاء متجر وهمي زي أي
--  تسجيل عادي ممكن يحصل أصلاً). التعديل والحذف (UPDATE/DELETE) هما
--  الخطر الحقيقي — ده اللي بيتقفل هنا.
--
--  أربع دوال جديدة:
--    • merchant_set_store_open / merchant_update_store_settings:
--      بيتحقق إن stores.owner_phone فعلاً بتاع صاحب الطلب (p_merchant_
--      phone) — نفس نمط merchant_accept_order الموجود بالفعل (تحقق
--      برقم التليفون، مش كلمة مرور — ده المستوى الحالي المعتمد لعمليات
--      التاجر العادية في التطبيق، مش إصلاح IDOR شامل بـ tokens، ده شغل
--      منفصل أكبر لسه متتبّع).
--    • admin_set_store_active / admin_delete_store: بتستخدم
--      _check_admin() المركزية زي كل دوال الأدمن التانية — لازمة لأن
--      admin.astro بيستخدم نفس anon key زي أي حد تاني (مفيش دور
--      قاعدة بيانات منفصل للأدمن)، فسحب UPDATE/DELETE من anon كان
--      هيكسر لوحة الأدمن نفسها من غير الدالتين دول.
--
--  القراءة (SELECT) فضلت زي ما هي مؤقتًا — أقل حساسية من الكتابة
--  (بيانات متجر عامة زي الاسم والعنوان، مش بيانات شخصية لعميل) وهتتعالج
--  في مرحلة لاحقة.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.merchant_set_store_open(p_merchant_phone text, p_store_id text, p_open boolean)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  update public.stores
     set is_open = p_open
   where id = p_store_id
     and owner_phone in (p_merchant_phone,
                         case when p_merchant_phone like '+20%' then '0'||substr(p_merchant_phone,4) else p_merchant_phone end,
                         case when p_merchant_phone like '0%'   then '+2'||p_merchant_phone           else p_merchant_phone end);
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.merchant_set_store_open(text, text, boolean) to anon, authenticated;

create or replace function public.merchant_update_store_settings(
  p_merchant_phone text, p_store_id text,
  p_name text default null, p_emoji text default null, p_display_phone text default null,
  p_address text default null, p_delivery_fee numeric default null, p_min_order numeric default null,
  p_delivery_time text default null, p_tagline text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  update public.stores
     set name          = coalesce(p_name, name),
         emoji         = coalesce(p_emoji, emoji),
         phone         = coalesce(p_display_phone, phone),
         address       = coalesce(p_address, address),
         delivery_fee  = coalesce(p_delivery_fee, delivery_fee),
         min_order     = coalesce(p_min_order, min_order),
         delivery_time = coalesce(p_delivery_time, delivery_time),
         tagline       = coalesce(p_tagline, tagline)
   where id = p_store_id
     and owner_phone in (p_merchant_phone,
                         case when p_merchant_phone like '+20%' then '0'||substr(p_merchant_phone,4) else p_merchant_phone end,
                         case when p_merchant_phone like '0%'   then '+2'||p_merchant_phone           else p_merchant_phone end);
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.merchant_update_store_settings(text, text, text, text, text, text, numeric, numeric, text, text) to anon, authenticated;

create or replace function public.admin_set_store_active(p_admin_phone text, p_admin_password text, p_store_id text, p_active boolean)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  update public.stores set is_active = p_active where id = p_store_id;
  return found;
end;
$$;
grant execute on function public.admin_set_store_active(text, text, text, boolean) to anon, authenticated;

create or replace function public.admin_delete_store(p_admin_phone text, p_admin_password text, p_store_id text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  delete from public.stores where id = p_store_id;
  return found;
end;
$$;
grant execute on function public.admin_delete_store(text, text, text) to anon, authenticated;

-- سحب صلاحيات التعديل/الحذف المباشرة على stores — أي تعديل أو حذف دلوقتي
-- لازم يعدي من الدوال فوق. الـ INSERT فضل مفتوح عمدًا (تسجيل متجر جديد).
drop policy if exists "anon all stores" on public.stores;
drop policy if exists "stores_update_all" on public.stores;
drop policy if exists "stores_delete_all" on public.stores;
create policy "stores_insert_public" on public.stores for insert to anon, authenticated with check (true);
revoke update, delete on public.stores from anon, authenticated;
