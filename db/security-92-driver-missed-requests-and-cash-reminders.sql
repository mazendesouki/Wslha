-- =====================================================================
--  وصّلها — Security #92: سجل الرحلات (طلبات فاتت وقت انقطاع النت)
--                        + أداة تذكير سداد الكاش من لوحة التحكم
--
--  (أ) سجل الرحلات: زي سجل التفاوض بالظبط — لكن بدل عرض المفتوح حاليًا،
--  بيعرض الطلبات اللي "فاتت" السائق. السائق يفضل شغّال سويتش "متصل"
--  (is_online=true)، لكن لو جهازه فقد الاتصال بالنت وقت ما محرك التوزيع
--  بعتله عرض (dispatch_offers)، العرض ده بينتهي صلاحيته (status='expired')
--  من غير ما السائق يشوفه أو يرد عليه. الجدول ده وآلية انتهاء الصلاحية
--  موجودين بالفعل (DISPATCHENGINESCHEMA.sql) — الجديد هنا بس دالة قراءة
--  ضيقة (السائق يشوف طلباته المنتهية هو بس، آخر 30 يوم).
--
--  (ب) أداة تذكير سداد الكاش: مفهوم جديد تمامًا — الأدمن يقدر يسجّل
--  "مبلغ مستحق" على سائق معيّن (كاش قبضه ولسه ما سلّموش للشركة)، والسائق
--  ياخد تذكير (نافذة منبثقة قابلة للإغلاق بزرار X) في التطبيق يفضل يظهر
--  لحد ما الأدمن يعلّمه "تم السداد" — مش مجرد إشعار يتنسى، لأنه فلوس
--  مستحقة فعلية.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- (أ) سجل الرحلات — الطلبات المنتهية الصلاحية بتاعة سائق معيّن
-- ---------------------------------------------------------------------
create or replace function public.get_driver_missed_requests(p_driver_phone text)
returns table(
  id text, target_type text, offered_at timestamptz, expires_at timestamptz,
  from_area text, to_area text, fare numeric, distance_km numeric,
  customer_name text, store_name text, order_total numeric
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    o.id, o.target_type, o.offered_at, o.expires_at,
    r.from_area, r.to_area, r.fare, r.distance_km, r.customer_name,
    s.name as store_name, ord.total as order_total
  from public.dispatch_offers o
  left join public.rides  r   on o.target_type = 'ride'  and r.id::text = o.target_id
  left join public.orders ord on o.target_type = 'order' and ord.id::text = o.target_id
  left join public.stores s   on s.id = ord.store_id
  where o.driver_phone = p_driver_phone
    and o.status = 'expired'
    and o.offered_at > now() - interval '30 days'
  order by o.offered_at desc
  limit 100;
$$;
grant execute on function public.get_driver_missed_requests(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- (ب) أداة تذكير سداد الكاش
-- ---------------------------------------------------------------------
create table if not exists public.driver_cash_reminders (
  id uuid primary key default gen_random_uuid(),
  driver_phone text not null,
  amount numeric not null check (amount > 0),
  note text,
  created_by_phone text,       -- رقم الأدمن اللي أنشأ التذكير
  created_at timestamptz not null default now(),
  due_at timestamptz not null default (now() + interval '7 days'),
  settled boolean not null default false,
  settled_at timestamptz,
  settled_by_phone text
);
create index if not exists idx_driver_cash_reminders_driver on public.driver_cash_reminders(driver_phone) where not settled;

revoke all on public.driver_cash_reminders from anon, authenticated;

-- الأدمن ينشئ تذكير — نفس نمط التحقق (كلمة مرور + مفتاح أمان) المتبع
-- في كل إجراء إداري حساس بيلمس فلوس.
create or replace function public.admin_create_cash_reminder(
  p_admin_phone text, p_admin_password text, p_driver_phone text,
  p_amount numeric, p_note text, p_action_key text
) returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_id uuid;
begin
  if not public.verify_action_key(p_action_key) then raise exception 'invalid_action_key'; end if;

  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_password';
  end if;

  if p_amount is null or p_amount <= 0 then raise exception 'invalid_amount'; end if;
  if not exists (select 1 from public.accounts where phone = p_driver_phone and role = 'driver') then
    raise exception 'driver_not_found';
  end if;

  insert into public.driver_cash_reminders (driver_phone, amount, note, created_by_phone)
  values (p_driver_phone, p_amount, p_note, v_admin.phone)
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.admin_create_cash_reminder(text, text, text, numeric, text, text) to anon, authenticated;

-- الأدمن يعلّم تذكير إنه "اتسدد" — بيوقف ظهوره في تطبيق السائق.
create or replace function public.admin_settle_cash_reminder(
  p_admin_phone text, p_admin_password text, p_reminder_id uuid
) returns boolean
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
  if v_admin.phone is null then return false; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;

  update public.driver_cash_reminders
     set settled = true, settled_at = now(), settled_by_phone = v_admin.phone
   where id = p_reminder_id and not settled;
  return found;
end;
$$;
grant execute on function public.admin_settle_cash_reminder(text, text, uuid) to anon, authenticated;

-- الأدمن يشوف كل التذكيرات النشطة (لعرضها في اللوحة).
create or replace function public.admin_list_cash_reminders(p_admin_phone text, p_admin_password text)
returns table(id uuid, driver_phone text, driver_name text, amount numeric, note text, created_at timestamptz, due_at timestamptz, settled boolean, settled_at timestamptz)
language plpgsql
stable
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
  if v_admin.phone is null or v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return;
  end if;

  return query
    select r.id, r.driver_phone, a.name, r.amount, r.note, r.created_at, r.due_at, r.settled, r.settled_at
    from public.driver_cash_reminders r
    left join public.accounts a on a.phone = r.driver_phone
    order by r.settled asc, r.created_at desc
    limit 200;
end;
$$;
grant execute on function public.admin_list_cash_reminders(text, text) to anon, authenticated;

-- السائق يشوف تذكيراته النشطة هو بس (مفيش بيانات سائقين تانيين).
create or replace function public.get_driver_active_cash_reminders(p_driver_phone text)
returns table(id uuid, amount numeric, note text, created_at timestamptz, due_at timestamptz)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select id, amount, note, created_at, due_at
  from public.driver_cash_reminders
  where driver_phone = p_driver_phone and not settled
  order by created_at desc;
$$;
grant execute on function public.get_driver_active_cash_reminders(text) to anon, authenticated;

-- إرسال إشعار Push فوري وقت إنشاء التذكير — نفس نمط trg_notify_driver_new_offer
-- بالضبط (security-21-driver-offer-push.sql): net.http_post لدالة send-push،
-- بنفس الـ headers (x-push-secret + apikey) وشكل الـ body (type/channel).
create or replace function public.notify_driver_cash_reminder()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  begin
    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-push-secret', public._push_trigger_secret(),
        'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
      ),
      body    := jsonb_build_object(
        'phone',   new.driver_phone,
        'title',   '💰 تذكير سداد رصيد كاش',
        'body',    'عندك مبلغ ' || new.amount || ' ج.م مستحق — برجاء السداد خلال أسبوع',
        'url',     '/driver-dashboard',
        'tag',     'wslha-cash-reminder-' || new.id,
        'type',    'cash_reminder',
        'channel', 'wslha_rides'
      )
    );
  exception when others then
    -- لو pg_net/الأسرار مش مظبوطة، منمنعش إنشاء التذكير نفسه — السائق
    -- هيشوفه لما يفتح التطبيق حتى لو الـ push فشل.
    null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_driver_cash_reminder on public.driver_cash_reminders;
create trigger trg_notify_driver_cash_reminder
  after insert on public.driver_cash_reminders
  for each row execute function public.notify_driver_cash_reminder();
