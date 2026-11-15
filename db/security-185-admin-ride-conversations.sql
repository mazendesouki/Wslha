-- =====================================================================
--  وصّلها — Security #185: اطّلاع الأدمن على محادثات الرحلات (سائق↔عميل)
--
--  مطلوب صراحة: إدارة التطبيق لازم يكون عندها وصول لمحادثات السائق
--  والعميل عشان تتعامل مع أي سوء تصرف محتمل — قبل الرحلة، أثناءها، أو
--  بعدها (الـ48 ساعة اللي فضل فيها الشات متاح بعد الانتهاء، security-
--  "feat: allow post-ride direct chat").
--
--  ride_messages أصلاً قابل للقراءة المباشرة لـ anon/authenticated —
--  قرار متعمّد موجود من security-69 (نفس نموذج الثقة "مينفعش حد يحزر
--  الـ ride_id" اللي rides/driver_locations شغالين بيه، ضروري عشان
--  Realtime streaming في الشات نفسه يشتغل). مش هنلمس ده هنا. اللي
--  ناقص فعليًا هو واجهة للأدمن تلاقي المحادثات وتتصفحها من غير ما
--  تعرف الـ ride_id مُقدّمًا — زي صفحة "الدعم الفني" بالظبط بس للمحادثات
--  بين الطرفين مش مع الدعم.
--
--  3 دوال، بنفس نمط admin_send_support_reply (تحقق فعلي بالتليفون/
--  الباسورد مش مجرد RLS):
--   1) admin_list_ride_conversations — الرحلات اللي فيها رسائل فعلاً
--      بس، مع آخر رسالة ووقتها، للبحث برقم العميل/السائق أو الـ ride_id.
--   2) admin_get_ride_messages — كل رسائل رحلة معيّنة بالترتيب.
--   3) admin_send_ride_message — لو الأدمن احتاج يتدخّل في المحادثة
--      نفسها (تحذير، توضيح) — بيتسجل برقم الأدمن و sender_role='admin'
--      عشان الطرفين يعرفوا إن ده تدخل إداري مش رسالة من بعضهم.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.admin_list_ride_conversations(
  p_admin_phone text, p_admin_password text,
  p_search text default null, p_limit int default 100
)
returns table (
  ride_id uuid, customer_phone text, customer_name text,
  driver_phone text, driver_name text, ride_status text,
  message_count bigint, last_message text, last_sender_role text, last_message_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_search text := nullif(trim(coalesce(p_search, '')), '');
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_credentials';
  end if;

  return query
    select r.id, r.customer_phone, r.customer_name, r.driver_phone, r.driver_name, r.status,
           m.message_count, m.last_message, m.last_sender_role, m.last_message_at
    from public.rides r
    join lateral (
      select count(*) as message_count,
             (array_agg(rm.body order by rm.created_at desc))[1] as last_message,
             (array_agg(rm.sender_role order by rm.created_at desc))[1] as last_sender_role,
             max(rm.created_at) as last_message_at
      from public.ride_messages rm
      where rm.ride_id = r.id
    ) m on m.message_count > 0
    where v_search is null
       or r.id::text ilike '%'||v_search||'%'
       or r.customer_phone ilike '%'||v_search||'%'
       or r.driver_phone ilike '%'||v_search||'%'
    order by m.last_message_at desc
    limit greatest(p_limit, 1);
end;
$$;
grant execute on function public.admin_list_ride_conversations(text, text, text, int) to anon, authenticated;

create or replace function public.admin_get_ride_messages(
  p_admin_phone text, p_admin_password text, p_ride_id uuid
)
returns setof public.ride_messages
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
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_credentials';
  end if;

  return query
    select * from public.ride_messages where ride_id = p_ride_id order by created_at;
end;
$$;
grant execute on function public.admin_get_ride_messages(text, text, uuid) to anon, authenticated;

create or replace function public.admin_send_ride_message(
  p_admin_phone text, p_admin_password text, p_ride_id uuid, p_body text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_body text := trim(p_body);
begin
  if v_body is null or length(v_body) = 0 then return false; end if;

  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_credentials';
  end if;

  if not exists (select 1 from public.rides where id = p_ride_id) then
    raise exception 'ride_not_found';
  end if;

  insert into public.ride_messages (ride_id, sender_phone, sender_role, body)
  values (p_ride_id, v_admin.phone, 'admin', v_body);
  return true;
end;
$$;
grant execute on function public.admin_send_ride_message(text, text, uuid, text) to anon, authenticated;
