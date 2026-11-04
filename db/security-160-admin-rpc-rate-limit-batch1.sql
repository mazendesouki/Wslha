-- =====================================================================
--  وصّلها — Security #160: ترحيل الدفعة الأولى (16 دالة) من فحص
--  كلمة مرور inline إلى _check_admin() المركزية (متابعة security-159)
--
--  كل الدوال هنا كانت بترجع false/null/تعمل return فاضي عند فشل
--  التحقق (مفيش exception) — يعني الاستبدال آمن 100%، مفيش خطر إن
--  أي insert يتلغي زي ما حصل مع admin_withdraw_platform_profit
--  (security-158). الدوال اللي بتستخدم v_admin.phone بعد كده (في
--  insert.created_by غالبًا) بتعمل select تانية بعد التأكد إن الأدمن
--  حقيقي — مأمونة لأن _check_admin() أكّد الحساب موجود.
--
--  verify_action_key() في الدوال اللي بتستخدمه فضلت زي ما هي (مش جزء
--  من السكوب هنا — ده gap منفصل، أصغر، ومعروف).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- 1) admin_adjust_wallet — v_admin غير مستخدمة بعد الفحص
create or replace function public.admin_adjust_wallet(p_admin_phone text, p_admin_password text, p_phone text, p_amount numeric, p_type text, p_note text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_id text;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  if p_phone is null or length(trim(p_phone)) = 0 then return false; end if;
  if p_amount is null or p_amount = 0 then return false; end if;
  if p_type not in ('admin_credit', 'admin_debit') then return false; end if;
  if p_note is null or length(trim(p_note)) < 5 then return false; end if;

  v_id := 'adm-' || (case when p_type = 'admin_credit' then 'cr' else 'db' end)
          || '-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6);

  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values (v_id, p_phone, p_amount, p_type, p_note, now());

  perform public.add_wallet_balance(p_phone, p_amount);

  return true;
end;
$$;

-- 2) admin_analytics_overview — v_admin غير مستخدمة بعد الفحص
create or replace function public.admin_analytics_overview(p_admin_phone text, p_admin_password text, p_days integer default 30)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_cutoff timestamptz;
  v_top_drivers jsonb;
  v_busiest_areas jsonb;
  v_payment_breakdown jsonb;
  v_total_customers int;
  v_repeat_customers int;
  v_unit text;
  v_trend jsonb;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return null; end if;

  v_cutoff := now() - (greatest(coalesce(p_days, 30), 1) || ' days')::interval;

  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_top_drivers from (
    select
      wt.phone,
      coalesce(a.name, '') as name,
      count(*)::int as trips,
      sum(wt.amount) as earnings,
      round(coalesce((
        select avg(r.rating) from public.ratings r
        where r.driver_phone = wt.phone and r.rated_by = 'customer' and r.created_at >= v_cutoff
      ), 0)::numeric, 2) as avg_rating
    from public.wallet_transactions wt
    left join public.accounts a on a.phone = wt.phone
    where wt.type = 'earning' and wt.created_at >= v_cutoff
    group by wt.phone, a.name
    order by sum(wt.amount) desc
    limit 10
  ) t;

  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_busiest_areas from (
    select from_area as area, count(*)::int as ride_count
    from public.rides
    where status = 'completed' and created_at >= v_cutoff and from_area is not null
    group by from_area
    order by count(*) desc
    limit 10
  ) t;

  select coalesce(jsonb_object_agg(payment, jsonb_build_object('count', cnt, 'amount', amt)), '{}'::jsonb) into v_payment_breakdown from (
    select coalesce(payment, 'cash') as payment, count(*)::int as cnt, sum(fare) as amt
    from public.rides
    where status = 'completed' and created_at >= v_cutoff
    group by coalesce(payment, 'cash')
  ) t;

  with cust as (
    select customer_phone from public.rides where status = 'completed' and created_at >= v_cutoff
    union all
    select customer_phone from public.orders where status = 'delivered' and created_at >= v_cutoff
  ),
  counts as (
    select customer_phone, count(*) as c from cust group by customer_phone
  )
  select count(*), count(*) filter (where c > 1) into v_total_customers, v_repeat_customers from counts;

  v_unit := case when coalesce(p_days, 30) <= 31 then 'day' else 'week' end;

  with buckets as (
    select generate_series(
      date_trunc(v_unit, v_cutoff),
      date_trunc(v_unit, now()),
      case when v_unit = 'day' then interval '1 day' else interval '1 week' end
    ) as bucket
  ),
  ride_agg as (
    select date_trunc(v_unit, created_at) as bucket, count(*)::int as cnt, sum(fare) as rev
    from public.rides
    where status = 'completed' and created_at >= v_cutoff
    group by 1
  ),
  order_agg as (
    select date_trunc(v_unit, created_at) as bucket, count(*)::int as cnt, sum(total) as rev
    from public.orders
    where status = 'delivered' and created_at >= v_cutoff
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'date', to_char(b.bucket, 'YYYY-MM-DD'),
    'revenue', round(coalesce(r.rev, 0) + coalesce(o.rev, 0), 2),
    'bookings', coalesce(r.cnt, 0) + coalesce(o.cnt, 0)
  ) order by b.bucket), '[]'::jsonb)
  into v_trend
  from buckets b
  left join ride_agg r on r.bucket = b.bucket
  left join order_agg o on o.bucket = b.bucket;

  return jsonb_build_object(
    'days', p_days,
    'top_drivers', v_top_drivers,
    'busiest_areas', v_busiest_areas,
    'payment_breakdown', v_payment_breakdown,
    'total_customers', coalesce(v_total_customers, 0),
    'repeat_customers', coalesce(v_repeat_customers, 0),
    'repeat_customer_rate', case when coalesce(v_total_customers, 0) > 0
      then round(100.0 * v_repeat_customers / v_total_customers, 1)
      else 0 end,
    'trend_unit', v_unit,
    'trend', v_trend
  );
end;
$$;

-- 3) admin_cancel_campaign
create or replace function public.admin_cancel_campaign(p_admin_phone text, p_admin_password text, p_campaign_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  update public.marketing_campaigns set status = 'cancelled'
   where id = p_campaign_id and status = 'scheduled';
  return true;
end;
$$;

-- 4) admin_cancel_email_campaign
create or replace function public.admin_cancel_email_campaign(p_admin_phone text, p_admin_password text, p_campaign_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  update public.email_campaigns set status = 'cancelled'
   where id = p_campaign_id and status = 'scheduled';
  return true;
end;
$$;

-- 5) admin_change_user_phone — verify_action_key يفضل زي ما هو (قبل الفحص)
create or replace function public.admin_change_user_phone(p_admin_phone text, p_admin_password text, p_target_phone text, p_new_phone text, p_action_key text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old_local text; v_old_intl text;
  v_new_local text; v_new_intl text;
  v_target record;
  v_col record;
begin
  if not public.verify_action_key(p_action_key) then return false; end if;
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  v_old_local := case when p_target_phone like '+20%' then '0'||substr(p_target_phone,4) else p_target_phone end;
  v_old_intl  := case when v_old_local like '0%' then '+2'||v_old_local else v_old_local end;

  v_new_local := case when p_new_phone like '+20%' then '0'||substr(p_new_phone,4) else p_new_phone end;
  v_new_intl  := case when v_new_local like '0%' then '+2'||v_new_local else v_new_local end;

  if v_new_local !~ '^01[0125][0-9]{8}$' then
    raise exception 'invalid_new_phone';
  end if;

  select * into v_target from public.accounts where phone in (v_old_local, v_old_intl) limit 1;
  if v_target.phone is null then raise exception 'account_not_found'; end if;

  if exists (select 1 from public.accounts where phone in (v_new_local, v_new_intl) and phone <> v_target.phone) then
    raise exception 'new_phone_already_used';
  end if;

  update public.accounts set phone = v_new_local, auth_user_id = null where phone = v_target.phone;

  for v_col in
    select table_name, column_name from information_schema.columns
     where table_schema = 'public' and column_name ilike '%phone%'
       and table_name <> 'accounts'
  loop
    execute format('update public.%I set %I = $1 where %I = $2', v_col.table_name, v_col.column_name, v_col.column_name)
      using v_new_local, v_old_local;
    execute format('update public.%I set %I = $1 where %I = $2', v_col.table_name, v_col.column_name, v_col.column_name)
      using v_new_intl, v_old_intl;
  end loop;

  return true;
end;
$$;

-- 6) admin_create_campaign — v_admin.phone مستخدمة (created_by)، re-select بعد التأكيد
create or replace function public.admin_create_campaign(p_admin_phone text, p_admin_password text, p_title text, p_body text, p_target_role text, p_url text, p_send_at timestamp with time zone, p_target_phone text default null::text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_title is null or length(trim(p_title)) = 0 or p_body is null or length(trim(p_body)) = 0 then
    return false;
  end if;
  if p_target_role = 'phone' and (p_target_phone is null or length(trim(p_target_phone)) = 0) then
    return false;
  end if;

  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  insert into public.marketing_campaigns (title, body, target_role, target_phone, url, send_at, created_by)
  values (trim(p_title), trim(p_body), p_target_role, nullif(trim(coalesce(p_target_phone, '')), ''),
          coalesce(nullif(trim(p_url), ''), '/'), coalesce(p_send_at, now()), v_admin.phone);
  return true;
end;
$$;

-- 7) admin_create_campaign_deprecated_v1 — v_admin.phone مستخدمة
create or replace function public.admin_create_campaign_deprecated_v1(p_admin_phone text, p_admin_password text, p_title text, p_body text, p_target_role text, p_url text, p_send_at timestamp with time zone)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_title is null or length(trim(p_title)) = 0 or p_body is null or length(trim(p_body)) = 0 then
    return false;
  end if;

  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  insert into public.marketing_campaigns (title, body, target_role, url, send_at, created_by)
  values (trim(p_title), trim(p_body), p_target_role, coalesce(nullif(trim(p_url), ''), '/'),
          coalesce(p_send_at, now()), v_admin.phone);
  return true;
end;
$$;

-- 8) admin_create_campaign_deprecated_v2 — v_admin.phone مستخدمة
create or replace function public.admin_create_campaign_deprecated_v2(p_admin_phone text, p_admin_password text, p_title text, p_body text, p_target_role text, p_url text, p_send_at timestamp with time zone, p_send_email boolean default false)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_title is null or length(trim(p_title)) = 0 or p_body is null or length(trim(p_body)) = 0 then
    return false;
  end if;

  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  insert into public.marketing_campaigns (title, body, target_role, url, send_at, created_by, send_email)
  values (trim(p_title), trim(p_body), p_target_role, coalesce(nullif(trim(p_url), ''), '/'),
          coalesce(p_send_at, now()), v_admin.phone, coalesce(p_send_email, false));
  return true;
end;
$$;

-- 9) admin_create_coupon — v_admin غير مستخدمة بعد الفحص
create or replace function public.admin_create_coupon(p_admin_phone text, p_admin_password text, p_code text, p_discount_type text, p_discount_value numeric, p_max_discount numeric, p_min_amount numeric, p_usage_limit integer, p_per_user_limit integer, p_applies_to text, p_expires_at timestamp with time zone, p_auto_apply_first_order boolean default false)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  insert into public.coupons (code, discount_type, discount_value, max_discount, min_amount, usage_limit, per_user_limit, applies_to, expires_at, auto_apply_first_order)
  values (upper(trim(p_code)), p_discount_type, p_discount_value, p_max_discount, coalesce(p_min_amount, 0),
          p_usage_limit, coalesce(p_per_user_limit, 1), coalesce(p_applies_to, 'all'), p_expires_at, coalesce(p_auto_apply_first_order, false));
  return true;
exception when unique_violation then
  return false;
end;
$$;

-- 10) admin_create_email_campaign — v_admin.phone مستخدمة
create or replace function public.admin_create_email_campaign(p_admin_phone text, p_admin_password text, p_subject text, p_body text, p_target_role text, p_send_at timestamp with time zone, p_image_url text default null::text, p_extra_emails text[] default null::text[])
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_subject is null or length(trim(p_subject)) = 0 or p_body is null or length(trim(p_body)) = 0 then
    return false;
  end if;

  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  insert into public.email_campaigns (subject, body, target_role, send_at, created_by, image_url, extra_emails)
  values (trim(p_subject), trim(p_body), p_target_role, coalesce(p_send_at, now()), v_admin.phone,
          nullif(trim(coalesce(p_image_url, '')), ''), p_extra_emails);
  return true;
end;
$$;

-- 11) admin_create_email_campaign_deprecated_v1 — v_admin.phone مستخدمة
create or replace function public.admin_create_email_campaign_deprecated_v1(p_admin_phone text, p_admin_password text, p_subject text, p_body text, p_target_role text, p_send_at timestamp with time zone)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_subject is null or length(trim(p_subject)) = 0 or p_body is null or length(trim(p_body)) = 0 then
    return false;
  end if;

  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  insert into public.email_campaigns (subject, body, target_role, send_at, created_by)
  values (trim(p_subject), trim(p_body), p_target_role, coalesce(p_send_at, now()), v_admin.phone);
  return true;
end;
$$;

-- 12) admin_create_email_campaign_deprecated_v2 — v_admin.phone مستخدمة
create or replace function public.admin_create_email_campaign_deprecated_v2(p_admin_phone text, p_admin_password text, p_subject text, p_body text, p_target_role text, p_send_at timestamp with time zone, p_image_url text default null::text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_subject is null or length(trim(p_subject)) = 0 or p_body is null or length(trim(p_body)) = 0 then
    return false;
  end if;

  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  insert into public.email_campaigns (subject, body, target_role, send_at, created_by, image_url)
  values (trim(p_subject), trim(p_body), p_target_role, coalesce(p_send_at, now()), v_admin.phone,
          nullif(trim(coalesce(p_image_url, '')), ''));
  return true;
end;
$$;

-- 13) admin_delete_account — verify_action_key يفضل زي ما هو؛ v_admin غير مستخدمة بعد الفحص
create or replace function public.admin_delete_account(p_admin_phone text, p_admin_password text, p_target_phone text, p_action_key text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_local  text;
  v_intl   text;
  v_rows   int;
begin
  if not public.verify_action_key(p_action_key) then return false; end if;
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  v_local := case when p_target_phone like '+20%' then '0'||substr(p_target_phone,4) else p_target_phone end;
  v_intl  := case when p_target_phone like '0%'   then '+2'||p_target_phone           else p_target_phone end;

  delete from public.driver_applications  where phone         in (v_local, v_intl);
  delete from public.merchant_applications where phone        in (v_local, v_intl);
  delete from public.driver_locations     where driver_phone  in (v_local, v_intl);
  delete from public.wallet_transactions  where phone         in (v_local, v_intl);
  delete from public.rides                where driver_phone  in (v_local, v_intl);
  delete from public.rides                where customer_phone in (v_local, v_intl);
  delete from public.orders               where customer_phone in (v_local, v_intl);
  delete from public.points               where phone         in (v_local, v_intl);
  delete from public.point_transactions   where phone         in (v_local, v_intl);
  delete from public.wallets              where phone         in (v_local, v_intl);
  delete from public.push_subscriptions   where phone         in (v_local, v_intl);

  perform set_config('app.privileged', 'on', true);
  delete from public.accounts where phone in (v_local, v_intl);
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);

  return v_rows > 0;
end;
$$;

-- 14) admin_get_application — v_admin غير مستخدمة بعد الفحص
create or replace function public.admin_get_application(p_admin_phone text, p_admin_password text, p_type text, p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_row jsonb;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return null; end if;

  if p_type = 'driver' then
    select to_jsonb(d.*) into v_row from public.driver_applications d
     where d.phone = p_phone order by d.created_at desc limit 1;
  elsif p_type = 'merchant' then
    select to_jsonb(m.*) into v_row from public.merchant_applications m
     where m.phone = p_phone order by m.created_at desc limit 1;
  else
    raise exception 'invalid type: %', p_type;
  end if;
  return v_row;
end;
$$;

-- 15) admin_get_fleet_cost_metrics — v_admin غير مستخدمة بعد الفحص
create or replace function public.admin_get_fleet_cost_metrics(p_admin_phone text, p_admin_password text)
returns table(metric text, current_value numeric, previous_value numeric, pct_change numeric)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_cur_fuel_avg_price numeric; v_prev_fuel_avg_price numeric;
  v_cur_fuel_spend numeric; v_prev_fuel_spend numeric;
  v_cur_maint_spend numeric; v_prev_maint_spend numeric;
  v_cur_maint_count numeric; v_prev_maint_count numeric;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  select avg(price_per_liter), sum(cost)
    into v_cur_fuel_avg_price, v_cur_fuel_spend
    from public.vehicle_service_logs
   where service_type = 'fuel' and performed_at >= now() - interval '30 days';

  select avg(price_per_liter), sum(cost)
    into v_prev_fuel_avg_price, v_prev_fuel_spend
    from public.vehicle_service_logs
   where service_type = 'fuel' and performed_at >= now() - interval '60 days' and performed_at < now() - interval '30 days';

  select sum(cost), count(*)
    into v_cur_maint_spend, v_cur_maint_count
    from public.vehicle_service_logs
   where service_type in ('maintenance','oil','tire','inspection','other')
     and performed_at >= now() - interval '30 days';

  select sum(cost), count(*)
    into v_prev_maint_spend, v_prev_maint_count
    from public.vehicle_service_logs
   where service_type in ('maintenance','oil','tire','inspection','other')
     and performed_at >= now() - interval '60 days' and performed_at < now() - interval '30 days';

  return query
    select 'avg_fuel_price_per_liter'::text, v_cur_fuel_avg_price, v_prev_fuel_avg_price,
           case when v_prev_fuel_avg_price is null or v_prev_fuel_avg_price = 0 then null
                else round((v_cur_fuel_avg_price - v_prev_fuel_avg_price) / v_prev_fuel_avg_price * 100, 1) end
    union all
    select 'total_fuel_spend'::text, v_cur_fuel_spend, v_prev_fuel_spend,
           case when v_prev_fuel_spend is null or v_prev_fuel_spend = 0 then null
                else round((v_cur_fuel_spend - v_prev_fuel_spend) / v_prev_fuel_spend * 100, 1) end
    union all
    select 'total_maintenance_spend'::text, v_cur_maint_spend, v_prev_maint_spend,
           case when v_prev_maint_spend is null or v_prev_maint_spend = 0 then null
                else round((v_cur_maint_spend - v_prev_maint_spend) / v_prev_maint_spend * 100, 1) end
    union all
    select 'maintenance_entries_count'::text, v_cur_maint_count, v_prev_maint_count,
           case when v_prev_maint_count is null or v_prev_maint_count = 0 then null
                else round((v_cur_maint_count - v_prev_maint_count) / v_prev_maint_count * 100, 1) end;
end;
$$;

-- 16) admin_get_referral_overview — v_admin غير مستخدمة بعد الفحص
create or replace function public.admin_get_referral_overview(p_admin_phone text, p_admin_password text)
returns table(total_referred integer, total_rewards_paid numeric, reward_amount numeric)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return; end if;

  return query
  select
    (select count(*)::int from public.accounts where referred_by is not null),
    (select coalesce(sum(amount), 0) from public.wallet_transactions where type = 'referral_credit'),
    public._pricing_setting_num('referral_reward_amount', 20, 0);
end;
$$;
