-- =====================================================================
--  وصّلها — Security #73: شات مباشر مع الدعم الفني
--
--  جدولين جداد:
--   - support_conversations: محادثة واحدة لكل رقم هاتف (بتتعاد استخدامها
--     في كل مرة يفتح فيها المستخدم الشات، مش محادثة جديدة كل مرة).
--   - support_messages: رسائل المحادثة (sender_role = 'user' أو 'support').
--
--  نموذج الثقة: زي accounts/wallets/favorites — رقم الهاتف مش حقيقي
--  (من غير Supabase Auth)، فمفيش SELECT/UPDATE/INSERT مباشر مفتوح على
--  الجدولين خالص. كل قراءة وكل كتابة لازم تعدي من خلال دالة (RPC) بتتأكد
--  إن رقم الهاتف اللي بعت فعلاً صاحب المحادثة دي قبل ما تدّيه أي بيانات.
--  ده أهم من نموذج "المعرف الصعب التخمين" اللي استخدمناه مع الرحلات
--  (rides/ride_messages) لأن محتوى شات الدعم ممكن يحتوي شكاوى/بيانات
--  شخصية حساسة، وقراءة الجدول كامل (لو كان RLS مفتوح using(true)) كانت
--  هتسرب كل محادثات كل المستخدمين لأي حد معاه الـ anon key.
--
--  دوال العميل (بدون باسورد، بس بتتأكد إن الهاتف بتاع صاحب المحادثة):
--   - get_or_create_support_conversation(phone) → معرف المحادثة
--   - get_support_messages(conversation_id, phone) → رسائل المحادثة
--   - send_support_message(conversation_id, phone, body)
--
--  دوال الأدمن (بباسورد، زي admin_list_accounts/admin_list_wallets):
--   - admin_list_support_conversations(admin_phone, admin_password)
--   - admin_get_support_messages(admin_phone, admin_password, conversation_id)
--   - admin_send_support_reply(admin_phone, admin_password, conversation_id, body)
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.support_conversations (
  id uuid primary key default gen_random_uuid(),
  user_phone text not null unique,
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.support_conversations(id) on delete cascade,
  sender_role text not null check (sender_role in ('user', 'support')),
  body text not null,
  read_by_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_support_messages_conversation on public.support_messages(conversation_id, created_at);

alter table public.support_conversations enable row level security;
alter table public.support_messages enable row level security;

-- مفيش أي سياسة RLS بتسمح بقراءة/كتابة مباشرة — كل الوصول عن طريق الدوال
-- اللي بتشتغل بصلاحية security definer بس (زي accounts بالظبط).
revoke all on public.support_conversations from anon, authenticated;
revoke all on public.support_messages from anon, authenticated;

-- ---------------------------------------------------------------------
-- دوال العميل
-- ---------------------------------------------------------------------
create or replace function public.get_or_create_support_conversation(p_phone text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_id uuid;
begin
  select id into v_id from public.support_conversations where user_phone = p_phone;
  if v_id is not null then return v_id; end if;

  insert into public.support_conversations (user_phone) values (p_phone)
    returning id into v_id;
  return v_id;
end;
$$;
grant execute on function public.get_or_create_support_conversation(text) to anon, authenticated;

create or replace function public.get_support_messages(p_conversation_id uuid, p_phone text)
returns setof public.support_messages
language sql
security definer
set search_path = public, extensions
as $$
  select m.* from public.support_messages m
   join public.support_conversations c on c.id = m.conversation_id
   where m.conversation_id = p_conversation_id
     and c.user_phone = p_phone
   order by m.created_at asc;
$$;
grant execute on function public.get_support_messages(uuid, text) to anon, authenticated;

create or replace function public.send_support_message(p_conversation_id uuid, p_phone text, p_body text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_body is null or length(trim(p_body)) = 0 then return; end if;

  update public.support_conversations
     set updated_at = now(), status = 'open'
   where id = p_conversation_id and user_phone = p_phone;
  if not found then return; end if;

  insert into public.support_messages (conversation_id, sender_role, body, read_by_admin)
    values (p_conversation_id, 'user', trim(p_body), false);
end;
$$;
grant execute on function public.send_support_message(uuid, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- دوال الأدمن — نفس نمط التحقق بالباسورد المستخدم في admin_list_accounts.
-- ---------------------------------------------------------------------
create or replace function public.admin_list_support_conversations(p_admin_phone text, p_admin_password text)
returns table(
  conversation_id uuid, user_phone text, status text, updated_at timestamptz,
  last_message text, unread_count bigint
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return;
  end if;

  return query
    select c.id, c.user_phone, c.status, c.updated_at,
           (select m.body from public.support_messages m
             where m.conversation_id = c.id order by m.created_at desc limit 1),
           (select count(*) from public.support_messages m
             where m.conversation_id = c.id and m.sender_role = 'user' and m.read_by_admin = false)
      from public.support_conversations c
     order by c.updated_at desc limit 500;
end;
$$;
grant execute on function public.admin_list_support_conversations(text, text) to anon, authenticated;

create or replace function public.admin_get_support_messages(p_admin_phone text, p_admin_password text, p_conversation_id uuid)
returns setof public.support_messages
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return;
  end if;

  update public.support_messages
     set read_by_admin = true
   where conversation_id = p_conversation_id and sender_role = 'user' and read_by_admin = false;

  return query
    select * from public.support_messages
     where conversation_id = p_conversation_id
     order by created_at asc;
end;
$$;
grant execute on function public.admin_get_support_messages(text, text, uuid) to anon, authenticated;

drop function if exists public.admin_send_support_reply(text, text, uuid, text);

create or replace function public.admin_send_support_reply(p_admin_phone text, p_admin_password text, p_conversation_id uuid, p_body text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_body is null or length(trim(p_body)) = 0 then return false; end if;

  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return false; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;

  update public.support_conversations set updated_at = now() where id = p_conversation_id;
  insert into public.support_messages (conversation_id, sender_role, body, read_by_admin)
    values (p_conversation_id, 'support', trim(p_body), true);
  return true;
end;
$$;
grant execute on function public.admin_send_support_reply(text, text, uuid, text) to anon, authenticated;

-- تشغيل ميزة الشات المباشر افتراضيًا (زي باقي الأعلام — security-72).
insert into public.app_settings (key, value) values
  ('feature_support_chat_enabled', 'true')
on conflict (key) do nothing;
