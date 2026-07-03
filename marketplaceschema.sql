-- =====================================================================
--  وصّلها — سوق المستعمل (Marketplace)
--
--  جدول الإعلانات + جدول البلاغات + دوال آمنة للنشر/الإبلاغ/الإشراف.
--  يتبع نفس نمط الأمان المُتَّبع في بقية التطبيق: لا RLS دقيقة بالمالك
--  (لعدم وجود مصادقة حقيقية بعد) لكن كل عملية حسّاسة تمرّ عبر دالة
--  SECURITY DEFINER بدل الكتابة المباشرة.
--
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) جدول الإعلانات
-- ---------------------------------------------------------------------
create table if not exists public.marketplace_items (
  id            text primary key default ('mkt-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,6)),
  seller_phone  text not null,
  seller_type   text not null default 'customer' check (seller_type in ('customer','merchant')),
  title         text not null,
  description   text,
  category       text not null default 'other',
  condition     text not null default 'used' check (condition in ('new','like_new','used','fair')),
  price         numeric not null check (price >= 0),
  quantity      int not null default 1 check (quantity >= 1),
  city          text,
  area          text,
  images        jsonb not null default '[]'::jsonb,
  contact_phone text not null,
  whatsapp      boolean not null default true,
  status        text not null default 'active' check (status in ('active','sold','removed','under_review')),
  reports_count int not null default 0,
  views         int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists marketplace_items_status_idx  on public.marketplace_items(status);
create index if not exists marketplace_items_seller_idx  on public.marketplace_items(seller_phone);
create index if not exists marketplace_items_category_idx on public.marketplace_items(category);

-- ---------------------------------------------------------------------
-- 2) جدول البلاغات
-- ---------------------------------------------------------------------
create table if not exists public.marketplace_reports (
  id           text primary key default ('rpt-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,6)),
  item_id      text not null references public.marketplace_items(id) on delete cascade,
  reporter_phone text,
  reason       text not null,
  created_at   timestamptz not null default now()
);
create index if not exists marketplace_reports_item_idx on public.marketplace_reports(item_id);

-- ---------------------------------------------------------------------
-- 3) طلبات توصيل عناصر السوق (ربط بخدمة التوصيل الحالية)
--    سجل بسيط يراه الأدمن ويُسنِد له سائقاً يدوياً حالياً — أتمتة كاملة
--    (ظهوره في لوحة السائق تلقائياً) تحتاج جولة لاحقة.
-- ---------------------------------------------------------------------
create table if not exists public.marketplace_orders (
  id            text primary key default ('mko-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,6)),
  item_id       text not null references public.marketplace_items(id),
  buyer_phone   text not null,
  buyer_name    text not null,
  buyer_address text not null,
  seller_phone  text not null,
  price         numeric not null,
  delivery_fee  numeric not null default 25,
  total         numeric not null,
  driver_phone  text,
  status        text not null default 'pending' check (status in ('pending','assigned','picked_up','delivered','cancelled')),
  created_at    timestamptz not null default now()
);
create index if not exists marketplace_orders_status_idx on public.marketplace_orders(status);

-- ---------------------------------------------------------------------
-- 4) مُحفّز حماية النشر: يفرض قيود الكمية حسب نوع البائع، ويربط
--    seller_type تلقائياً بدور الحساب الحقيقي (لا يثق بما يرسله العميل).
-- ---------------------------------------------------------------------
create or replace function public.guard_marketplace_item()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_role text;
begin
  select role into v_role from public.accounts
   where phone in (new.seller_phone,
                   case when new.seller_phone like '+20%' then '0'||substr(new.seller_phone,4) else new.seller_phone end,
                   case when new.seller_phone like '0%'   then '+2'||new.seller_phone           else new.seller_phone end)
   limit 1;

  if v_role = 'merchant' then
    new.seller_type := 'merchant';
    if new.quantity > 500 then new.quantity := 500; end if;
  else
    new.seller_type := 'customer';
    new.quantity := 1; -- الأفراد: قطعة واحدة لكل إعلان (لا يُستخدم كمتجر مصغّر)
  end if;

  new.status := 'active';       -- النشر فوري دائماً (لا يمكن للعميل تعيين حالة مبدئية أخرى)
  new.reports_count := 0;
  return new;
end;
$$;

drop trigger if exists trg_guard_marketplace_item on public.marketplace_items;
create trigger trg_guard_marketplace_item
  before insert on public.marketplace_items
  for each row execute function public.guard_marketplace_item();

-- ---------------------------------------------------------------------
-- 5) الإبلاغ عن إعلان — بعد 3 بلاغات يُخفى تلقائياً لمراجعة الأدمن
-- ---------------------------------------------------------------------
create or replace function public.report_marketplace_item(p_item_id text, p_reporter_phone text, p_reason text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_count int;
begin
  insert into public.marketplace_reports (item_id, reporter_phone, reason)
  values (p_item_id, p_reporter_phone, coalesce(nullif(trim(p_reason),''), 'غير محدد'));

  update public.marketplace_items
     set reports_count = reports_count + 1
   where id = p_item_id
  returning reports_count into v_count;

  if v_count >= 3 then
    update public.marketplace_items set status = 'under_review' where id = p_item_id;
  end if;
  return true;
end;
$$;
grant execute on function public.report_marketplace_item(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 6) البائع يعلّم إعلانه "تم البيع" أو يحذفه — (تحقق أفضل جهد بالرقم،
--    نفس مستوى الثقة المستخدم في بقية التطبيق حتى تكتمل هجرة Auth)
-- ---------------------------------------------------------------------
create or replace function public.update_own_marketplace_item(p_phone text, p_item_id text, p_status text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  if p_status not in ('sold','removed','active') then raise exception 'bad_status'; end if;
  update public.marketplace_items
     set status = p_status, updated_at = now()
   where id = p_item_id
     and seller_phone in (p_phone,
                          case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end,
                          case when p_phone like '0%'   then '+2'||p_phone           else p_phone end);
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
grant execute on function public.update_own_marketplace_item(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 7) إشراف الأدمن: اعتماد إعلان معلَّق للمراجعة أو حذفه نهائياً
-- ---------------------------------------------------------------------
create or replace function public.admin_moderate_item(
  p_admin_phone text, p_admin_password text, p_item_id text, p_action text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_action not in ('approve','remove') then raise exception 'bad_action'; end if;
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return false; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;

  if p_action = 'approve' then
    update public.marketplace_items set status = 'active', reports_count = 0 where id = p_item_id;
  else
    update public.marketplace_items set status = 'removed' where id = p_item_id;
  end if;
  return true;
end;
$$;
grant execute on function public.admin_moderate_item(text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 8) طلب توصيل لعنصر سوق — أجرة توصيل ثابتة بسيطة (25 ج.م) يمكن تعديلها لاحقاً
-- ---------------------------------------------------------------------
create or replace function public.request_marketplace_delivery(
  p_item_id text, p_buyer_phone text, p_buyer_name text, p_buyer_address text
) returns public.marketplace_orders
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_item record; v_row public.marketplace_orders; v_fee numeric := 25;
begin
  select * into v_item from public.marketplace_items where id = p_item_id and status = 'active';
  if v_item.id is null then raise exception 'item_not_available'; end if;

  insert into public.marketplace_orders (item_id, buyer_phone, buyer_name, buyer_address, seller_phone, price, delivery_fee, total)
  values (p_item_id, p_buyer_phone, p_buyer_name, p_buyer_address, v_item.seller_phone, v_item.price, v_fee, v_item.price + v_fee)
  returning * into v_row;

  return v_row;
end;
$$;
grant execute on function public.request_marketplace_delivery(text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 9) صلاحيات: قراءة عامة، لا كتابة مباشرة إلا عبر الدوال أعلاه
-- ---------------------------------------------------------------------
grant select, insert on public.marketplace_items to anon, authenticated;   -- الإدراج يمرّ عبر المُحفّز أعلاه
revoke update, delete on public.marketplace_items from anon, authenticated;

grant select on public.marketplace_orders to anon, authenticated;
revoke insert, update, delete on public.marketplace_orders from anon, authenticated;

revoke select, insert, update, delete on public.marketplace_reports from anon, authenticated; -- عبر RPC فقط

-- ---------------------------------------------------------------------
-- 10) دلو تخزين الصور (إن لم يكن موجوداً) — نفس نمط 'documents'
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('marketplace', 'marketplace', true)
on conflict (id) do nothing;

-- =====================================================================
--  اختبار سريع (اختياري):
--    select public.report_marketplace_item('mkt-xxx', '01xxxxxxxxx', 'محتوى مخالف');
--    select public.admin_moderate_item('01102667324','<كلمة السر>','mkt-xxx','approve');
-- =====================================================================
