-- =====================================================================
--  وصّلها — Security #161: ترحيل الدفعة الثانية (29 دالة) من فحص
--  كلمة مرور inline إلى _check_admin() المركزية (متابعة security-160)
--
--  كل الدوال هنا بترجع false/null/تعمل return فاضي عند فشل التحقق
--  (مفيش exception على مسار كلمة المرور) — نفس الضمان زي الدفعة
--  الأولى: الاستبدال آمن 100%.
--
--  admin_settle_cash_reminder هي الوحيدة اللي بتستخدم v_admin.phone
--  بعد الفحص (settled_by_phone) — بتعمل select تانية بعد التأكد.
--  admin_verify_password كانت الفحص نفسه بالكامل، فبقت تستدعي
--  _check_admin() مباشرة من غير أي كود تكراري.
--
--  admin_list_applications و admin_review_application عندهم raise
--  exception لكن على حالات validation بعد التأكد من الأدمن (نوع غير
--  صالح) — مش على كلمة المرور، فمفيش insert قبلهم يحتاج يتحمي.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- 1) admin_get_support_messages
create or replace function public.admin_get_support_messages(p_admin_phone text, p_admin_password text, p_conversation_id uuid)
returns setof support_messages
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  update public.support_messages
     set read_by_admin = true
   where conversation_id = p_conversation_id and sender_role = 'user' and read_by_admin = false;

  return query
    select * from public.support_messages
     where conversation_id = p_conversation_id
     order by created_at asc;
end;
$$;

-- 2) admin_list_alerts
create or replace function public.admin_list_alerts(p_admin_phone text, p_admin_password text, p_limit integer default 20)
returns setof admin_alerts
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;
  return query select * from public.admin_alerts order by created_at desc limit p_limit;
end;
$$;

-- 3) admin_list_app_reviews
create or replace function public.admin_list_app_reviews(p_admin_phone text, p_admin_password text, p_limit integer default 100)
returns setof app_reviews
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;
  return query select * from public.app_reviews order by is_approved asc, created_at desc limit p_limit;
end;
$$;

-- 4) admin_list_applications
create or replace function public.admin_list_applications(p_admin_phone text, p_admin_password text, p_type text)
returns setof jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  if p_type = 'driver' then
    return query select to_jsonb(d.*) from public.driver_applications d order by d.created_at desc limit 500;
  elsif p_type = 'merchant' then
    return query select to_jsonb(m.*) from public.merchant_applications m order by m.created_at desc limit 500;
  else
    raise exception 'invalid type: %', p_type;
  end if;
end;
$$;

-- 5) admin_list_campaigns
create or replace function public.admin_list_campaigns(p_admin_phone text, p_admin_password text)
returns setof marketing_campaigns
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;
  return query select * from public.marketing_campaigns order by send_at desc limit 300;
end;
$$;

-- 6) admin_list_cash_reminders
create or replace function public.admin_list_cash_reminders(p_admin_phone text, p_admin_password text)
returns table(id uuid, driver_phone text, driver_name text, amount numeric, note text, created_at timestamp with time zone, due_at timestamp with time zone, settled boolean, settled_at timestamp with time zone)
language plpgsql
stable security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  return query
    select r.id, r.driver_phone, a.name, r.amount, r.note, r.created_at, r.due_at, r.settled, r.settled_at
    from public.driver_cash_reminders r
    left join public.accounts a on a.phone = r.driver_phone
    order by r.settled asc, r.created_at desc
    limit 200;
end;
$$;

-- 7) admin_list_coupons
create or replace function public.admin_list_coupons(p_admin_phone text, p_admin_password text)
returns table(id uuid, code text, discount_type text, discount_value numeric, max_discount numeric, min_amount numeric, usage_limit integer, per_user_limit integer, applies_to text, active boolean, expires_at timestamp with time zone, created_at timestamp with time zone, times_used bigint, auto_apply_first_order boolean)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  return query
    select c.id, c.code, c.discount_type, c.discount_value, c.max_discount, c.min_amount,
           c.usage_limit, c.per_user_limit, c.applies_to, c.active, c.expires_at, c.created_at,
           (select count(*) from public.coupon_redemptions r where r.coupon_id = c.id),
           c.auto_apply_first_order
      from public.coupons c
     order by c.created_at desc limit 500;
end;
$$;

-- 8) admin_list_email_campaigns
create or replace function public.admin_list_email_campaigns(p_admin_phone text, p_admin_password text)
returns setof email_campaigns
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;
  return query select * from public.email_campaigns order by send_at desc limit 300;
end;
$$;

-- 9) admin_list_maintenance_catalog
create or replace function public.admin_list_maintenance_catalog(p_admin_phone text, p_admin_password text)
returns setof maintenance_catalog_items
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;
  return query select * from public.maintenance_catalog_items order by sort_order;
end;
$$;

-- 10) admin_list_service_controls
create or replace function public.admin_list_service_controls(p_admin_phone text, p_admin_password text)
returns setof service_controls
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;
  return query select * from public.service_controls order by service_key;
end;
$$;

-- 11) admin_list_support_conversations
create or replace function public.admin_list_support_conversations(p_admin_phone text, p_admin_password text)
returns table(conversation_id uuid, user_phone text, status text, updated_at timestamp with time zone, last_message text, unread_count bigint)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

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

-- 12) admin_list_vehicle_service_logs
create or replace function public.admin_list_vehicle_service_logs(p_admin_phone text, p_admin_password text, p_driver_phone text default null::text, p_service_type text default null::text, p_limit integer default 300)
returns table(id uuid, driver_phone text, driver_name text, service_type text, custom_label text, cost numeric, odometer_km numeric, fuel_liters numeric, notes text, performed_at timestamp with time zone, created_by text, created_at timestamp with time zone)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  return query
    select l.id, l.driver_phone, da.full_name, l.service_type, l.custom_label,
           l.cost, l.odometer_km, l.fuel_liters, l.notes, l.performed_at, l.created_by, l.created_at
      from public.vehicle_service_logs l
      left join lateral (
        select full_name from public.driver_applications da
         where da.phone::text in (
           l.driver_phone,
           case when l.driver_phone like '+20%' then '0'||substr(l.driver_phone,4) else l.driver_phone end,
           case when l.driver_phone like '0%'   then '+2'||l.driver_phone           else l.driver_phone end
         )
         order by da.created_at desc limit 1
      ) da on true
     where (p_driver_phone is null or l.driver_phone = p_driver_phone)
       and (p_service_type is null or l.service_type = p_service_type)
     order by l.performed_at desc
     limit greatest(1, least(coalesce(p_limit, 300), 1000));
end;
$$;

-- 13) admin_list_vehicle_service_logs_v2_deprecated
create or replace function public.admin_list_vehicle_service_logs_v2_deprecated(p_admin_phone text, p_admin_password text, p_driver_phone text default null::text, p_service_type text default null::text, p_limit integer default 300)
returns table(id uuid, driver_phone text, driver_name text, service_type text, custom_label text, cost numeric, odometer_km numeric, fuel_liters numeric, price_per_liter numeric, notes text, performed_at timestamp with time zone, created_by text, created_at timestamp with time zone)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  return query
    select l.id, l.driver_phone, da.full_name, l.service_type, l.custom_label,
           l.cost, l.odometer_km, l.fuel_liters, l.price_per_liter, l.notes, l.performed_at, l.created_by, l.created_at
      from public.vehicle_service_logs l
      left join lateral (
        select full_name from public.driver_applications da
         where da.phone::text in (
           l.driver_phone,
           case when l.driver_phone like '+20%' then '0'||substr(l.driver_phone,4) else l.driver_phone end,
           case when l.driver_phone like '0%'   then '+2'||l.driver_phone           else l.driver_phone end
         )
         order by da.created_at desc limit 1
      ) da on true
     where (p_driver_phone is null or l.driver_phone = p_driver_phone)
       and (p_service_type is null or l.service_type = p_service_type)
     order by l.performed_at desc
     limit greatest(1, least(coalesce(p_limit, 300), 1000));
end;
$$;

-- 14) admin_list_vehicle_service_logs_v3
create or replace function public.admin_list_vehicle_service_logs_v3(p_admin_phone text, p_admin_password text, p_driver_phone text default null::text, p_service_type text default null::text, p_limit integer default 300)
returns table(id uuid, driver_phone text, driver_name text, service_type text, custom_label text, cost numeric, odometer_km numeric, fuel_liters numeric, price_per_liter numeric, quantity numeric, unit_price numeric, notes text, performed_at timestamp with time zone, created_by text, created_at timestamp with time zone)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  return query
    select l.id, l.driver_phone, da.full_name, l.service_type, l.custom_label,
           l.cost, l.odometer_km, l.fuel_liters, l.price_per_liter, l.quantity, l.unit_price, l.notes, l.performed_at, l.created_by, l.created_at
      from public.vehicle_service_logs l
      left join lateral (
        select full_name from public.driver_applications da
         where da.phone::text in (
           l.driver_phone,
           case when l.driver_phone like '+20%' then '0'||substr(l.driver_phone,4) else l.driver_phone end,
           case when l.driver_phone like '0%'   then '+2'||l.driver_phone           else l.driver_phone end
         )
         order by da.created_at desc limit 1
      ) da on true
     where (p_driver_phone is null or l.driver_phone = p_driver_phone)
       and (p_service_type is null or l.service_type = p_service_type)
     order by l.performed_at desc
     limit greatest(1, least(coalesce(p_limit, 300), 1000));
end;
$$;

-- 15) admin_list_vehicle_service_logs_v4
create or replace function public.admin_list_vehicle_service_logs_v4(p_admin_phone text, p_admin_password text, p_driver_phone text default null::text, p_service_type text default null::text, p_limit integer default 300)
returns table(id uuid, driver_phone text, driver_name text, service_type text, custom_label text, cost numeric, odometer_km numeric, fuel_liters numeric, price_per_liter numeric, quantity numeric, unit_price numeric, service_center text, notes text, performed_at timestamp with time zone, created_by text, created_at timestamp with time zone)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  return query
    select l.id, l.driver_phone, da.full_name, l.service_type, l.custom_label,
           l.cost, l.odometer_km, l.fuel_liters, l.price_per_liter, l.quantity, l.unit_price,
           l.service_center, l.notes, l.performed_at, l.created_by, l.created_at
      from public.vehicle_service_logs l
      left join lateral (
        select full_name from public.driver_applications da
         where da.phone::text in (
           l.driver_phone,
           case when l.driver_phone like '+20%' then '0'||substr(l.driver_phone,4) else l.driver_phone end,
           case when l.driver_phone like '0%'   then '+2'||l.driver_phone           else l.driver_phone end
         )
         order by da.created_at desc limit 1
      ) da on true
     where (p_driver_phone is null or l.driver_phone = p_driver_phone)
       and (p_service_type is null or l.service_type = p_service_type)
     order by l.performed_at desc
     limit greatest(1, least(coalesce(p_limit, 300), 1000));
end;
$$;

-- 16) admin_list_wallet_transactions
create or replace function public.admin_list_wallet_transactions(p_admin_phone text, p_admin_password text, p_phone text default null::text, p_limit integer default 500)
returns setof wallet_transactions
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  if p_phone is not null then
    return query select * from public.wallet_transactions
      where phone = p_phone order by created_at desc limit greatest(1, least(p_limit, 2000));
  else
    return query select * from public.wallet_transactions
      order by created_at desc limit greatest(1, least(p_limit, 2000));
  end if;
end;
$$;

-- 17) admin_list_wallets
create or replace function public.admin_list_wallets(p_admin_phone text, p_admin_password text)
returns table(phone text, balance numeric, updated_at timestamp with time zone)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  return query
    select w.phone, w.balance, w.updated_at from public.wallets w
     order by w.balance desc limit 2000;
end;
$$;

-- 18) admin_review_application — v_admin غير مستخدمة بعد الفحص
create or replace function public.admin_review_application(p_admin_phone text, p_admin_password text, p_type text, p_phone text, p_status text, p_reason text default null::text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_local text;
  v_intl  text;
  v_rows  int;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  if p_status not in ('approved', 'rejected') then
    raise exception 'invalid status: %', p_status;
  end if;
  if p_type not in ('driver', 'merchant') then
    raise exception 'invalid type: %', p_type;
  end if;

  v_local := case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end;
  v_intl  := case when p_phone like '0%'   then '+2'||p_phone           else p_phone end;

  perform set_config('wslha.allow_status_change', 'on', true);

  if p_type = 'driver' then
    update public.driver_applications
       set status = p_status, rejection_reason = p_reason, updated_at = now()
     where phone in (v_local, v_intl);
    get diagnostics v_rows = row_count;

    if p_status = 'approved' then
      update public.accounts set role = 'driver', status = 'approved'
       where phone in (v_local, v_intl);
    end if;
  else
    update public.merchant_applications
       set status = p_status, updated_at = now()
     where phone in (v_local, v_intl);
    get diagnostics v_rows = row_count;

    if p_status = 'approved' then
      update public.accounts set role = 'merchant', status = 'approved'
       where phone in (v_local, v_intl);
    end if;
  end if;

  return v_rows > 0;
end;
$$;

-- 19) admin_send_support_reply — v_admin غير مستخدمة بعد الفحص
create or replace function public.admin_send_support_reply(p_admin_phone text, p_admin_password text, p_conversation_id uuid, p_body text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_customer_phone text;
begin
  if p_body is null or length(trim(p_body)) = 0 then return false; end if;

  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  update public.support_conversations set updated_at = now(), ai_enabled = false
   where id = p_conversation_id
   returning user_phone into v_customer_phone;
  insert into public.support_messages (conversation_id, sender_role, body, read_by_admin)
    values (p_conversation_id, 'support', trim(p_body), true);

  if v_customer_phone is not null then
    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-push-secret', public._push_trigger_secret(),
        'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
      ),
      body    := jsonb_build_object(
        'phone', v_customer_phone,
        'title', '🎧 رد جديد من الدعم الفني',
        'body',  trim(p_body),
        'url',   '/support',
        'tag',   'wslha-support-reply-' || p_conversation_id
      )
    );
  end if;

  return true;
end;
$$;

-- 20) admin_set_app_review_approved
create or replace function public.admin_set_app_review_approved(p_admin_phone text, p_admin_password text, p_review_id uuid, p_approved boolean)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  update public.app_reviews set is_approved = p_approved, updated_at = now() where id = p_review_id;
  return found;
end;
$$;

-- 21) admin_set_coupon_active
create or replace function public.admin_set_coupon_active(p_admin_phone text, p_admin_password text, p_coupon_id uuid, p_active boolean)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  update public.coupons set active = p_active where id = p_coupon_id;
  return true;
end;
$$;

-- 22) admin_set_setting
create or replace function public.admin_set_setting(p_admin_phone text, p_admin_password text, p_key text, p_value text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  insert into public.app_settings (key, value, updated_at) values (p_key, p_value, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return true;
end;
$$;

-- 23) admin_set_user_status
create or replace function public.admin_set_user_status(p_admin_phone text, p_admin_password text, p_target_phone text, p_status text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  perform set_config('app.privileged', 'on', true);
  update public.accounts set status = p_status where phone = p_target_phone;
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);
  return v_rows > 0;
end;
$$;

-- 24) admin_settle_cash_reminder — v_admin.phone مستخدمة (settled_by_phone)، re-select بعد التأكيد
create or replace function public.admin_settle_cash_reminder(p_admin_phone text, p_admin_password text, p_reminder_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  update public.driver_cash_reminders
     set settled = true, settled_at = now(), settled_by_phone = v_admin.phone
   where id = p_reminder_id and not settled;
  return found;
end;
$$;

-- 25) admin_upsert_maintenance_catalog_item
create or replace function public.admin_upsert_maintenance_catalog_item(p_admin_phone text, p_admin_password text, p_item_key text, p_label_ar text, p_importance text, p_interval_km numeric, p_interval_months numeric, p_sort_order integer default 0, p_active boolean default true)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  if p_importance not in ('critical','important') then raise exception 'invalid_importance'; end if;

  insert into public.maintenance_catalog_items
    (item_key, label_ar, importance, interval_km, interval_months, sort_order, active, updated_at)
  values
    (p_item_key, p_label_ar, p_importance, p_interval_km, p_interval_months, p_sort_order, p_active, now())
  on conflict (item_key) do update
    set label_ar = excluded.label_ar,
        importance = excluded.importance,
        interval_km = excluded.interval_km,
        interval_months = excluded.interval_months,
        sort_order = excluded.sort_order,
        active = excluded.active,
        updated_at = now();

  return true;
end;
$$;

-- 26) admin_vehicle_service_summary
create or replace function public.admin_vehicle_service_summary(p_admin_phone text, p_admin_password text)
returns table(service_type text, entries_count bigint, total_cost numeric, total_fuel_liters numeric)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  return query
    select l.service_type, count(*)::bigint, coalesce(sum(l.cost), 0), coalesce(sum(l.fuel_liters), 0)
      from public.vehicle_service_logs l
     group by l.service_type
     order by l.service_type;
end;
$$;

-- 27) admin_verify_password — الدالة كلها كانت الفحص نفسه، بقت تفويض مباشر
create or replace function public.admin_verify_password(p_admin_phone text, p_admin_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  return public._check_admin(p_admin_phone, p_admin_password);
end;
$$;

-- 28) create_admin — v_admin غير مستخدمة بعد الفحص
create or replace function public.create_admin(p_admin_phone text, p_admin_password text, p_name text, p_phone text, p_password text, p_action_key text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.verify_action_key(p_action_key) then return false; end if;
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  perform set_config('app.privileged', 'on', true);
  insert into public.accounts (phone, name, password, role, status, created_at)
  values (p_phone, p_name, p_password, 'admin', 'active', now());
  perform set_config('app.privileged', 'off', true);
  return true;
end;
$$;

-- 29) grant_admin — v_admin غير مستخدمة بعد الفحص
create or replace function public.grant_admin(p_admin_phone text, p_admin_password text, p_target_phone text, p_action_key text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_local text; v_intl text; v_rows int;
begin
  if not public.verify_action_key(p_action_key) then return false; end if;
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  v_local := case when p_target_phone like '+20%' then '0'||substr(p_target_phone,4) else p_target_phone end;
  v_intl  := case when p_target_phone like '0%'   then '+2'||p_target_phone           else p_target_phone end;

  perform set_config('app.privileged', 'on', true);
  update public.accounts set role = 'admin', status = 'active' where phone in (v_local, v_intl);
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);
  return v_rows > 0;
end;
$$;
