-- =====================================================================
--  وصّلها — Security #162: ترحيل الدفعة الثالثة والأخيرة (10 دوال) من
--  فحص كلمة مرور inline إلى _check_admin() المركزية (متابعة
--  security-161) — تغطي كل الدوال الـ57 المتبقية.
--
--  هنا بالضبط المجموعة اللي كانت خطرة لو اتعملت بسطحية: 3 دوال
--  (admin_moderate_item, admin_set_service_control, admin_set_user_role)
--  كانت بالفعل بترجع false عند فشل الدخول (مفيش raise) — دول أمان
--  100% زي باقي الدفعات، بس استبدال الكود المكرر بـ _check_admin().
--
--  السبعة الباقية كانت بتعمل RAISE EXCEPTION على 'not_admin'/'bad_password'
--  — بالضبط نفس المشكلة اللي security-158 اكتشفها: استدعاء _check_admin()
--  وهو بيعمل insert لمحاولة فاشلة، وبعدين نعمل raise في نفس الاستدعاء،
--  هيلغي (rollback) الـ insert ده، فالعداد مش هيتسجل خالص. الحل: شيلنا
--  الـ raise بتاع كلمة المرور وبدّلناه بإرجاع قيمة آمنة (مفيش exception)
--  — فالـ insert جوه _check_admin() يتثبّت فعليًا:
--
--    • admin_delete_promotion, admin_end_promotion: ظلت boolean،
--      بترجع false بدل الـ raise (العميل بيعامل false زي exception
--      بالظبط — sbRpc بترجع false في الحالتين، فمفيش تغيير مطلوب
--      في admin.astro).
--    • admin_create_cash_reminder, admin_create_promotion,
--      admin_get_account_detail, admin_list_accounts,
--      admin_list_promotions: لازم تتحول لـ jsonb {ok,error,message,...}
--      عشان العميل يقدر يميّز "قفل/كلمة مرور غلط" من "نجح" من غير أي
--      exception تتبلع جوه نفس المعاملة. العميل (admin.astro) اتعدّل
--      ليقرا result.ok بدل الاعتماد على catch(e) أو rows === null.
--
--  verify_action_key() في admin_create_cash_reminder فضل زي ما هو —
--  أول سطر في الدالة، قبل أي insert، فمفيش خطر rollback لمحاولة فاشلة.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- 1) admin_moderate_item — كانت بترجع false خالص، أمان 100%
create or replace function public.admin_moderate_item(p_admin_phone text, p_admin_password text, p_item_id text, p_action text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_action not in ('approve','remove') then raise exception 'bad_action'; end if;
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  if p_action = 'approve' then
    update public.marketplace_items set status = 'active', reports_count = 0 where id = p_item_id;
  else
    update public.marketplace_items set status = 'removed' where id = p_item_id;
  end if;
  return true;
end;
$$;

-- 2) admin_set_service_control — كانت بترجع false خالص، أمان 100%
create or replace function public.admin_set_service_control(p_admin_phone text, p_admin_password text, p_service_key text, p_status text, p_scheduled_start timestamp with time zone default null::timestamp with time zone, p_scheduled_end timestamp with time zone default null::timestamp with time zone)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_status not in ('on', 'off', 'scheduled') then
    raise exception 'invalid status: %', p_status;
  end if;
  if p_status = 'scheduled' and p_scheduled_start is null then
    raise exception 'scheduled status needs a start time';
  end if;

  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  update public.service_controls
     set status = p_status, scheduled_start = p_scheduled_start, scheduled_end = p_scheduled_end,
         updated_by = v_admin.phone, updated_at = now()
   where service_key = p_service_key;
  return found;
end;
$$;

-- 3) admin_set_user_role — كانت بترجع false خالص، أمان 100%
create or replace function public.admin_set_user_role(p_admin_phone text, p_admin_password text, p_target_phone text, p_role text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  if p_role = 'admin' then
    raise exception 'use_grant_admin_instead';
  end if;

  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  perform set_config('app.privileged', 'on', true);
  update public.accounts
     set role = p_role, status = case when p_role = 'driver' then 'approved' else status end
   where phone = p_target_phone;
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);
  return v_rows > 0;
end;
$$;

-- 4) admin_delete_promotion — raise -> false (sbRpc بيعاملهم نفس المعاملة)
create or replace function public.admin_delete_promotion(p_admin_phone text, p_admin_password text, p_id text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  delete from public.app_promotions where id = p_id;
  return found;
end;
$$;

-- 5) admin_end_promotion — raise -> false
create or replace function public.admin_end_promotion(p_admin_phone text, p_admin_password text, p_id text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;

  update public.app_promotions set active = false where id = p_id;
  return found;
end;
$$;

-- 6) admin_create_cash_reminder — uuid -> jsonb{ok,error,message,id}
-- return type تغيّر (uuid -> jsonb) فـ CREATE OR REPLACE غير كافي، لازم DROP الأول
drop function if exists public.admin_create_cash_reminder(text, text, text, numeric, text, text);
create or replace function public.admin_create_cash_reminder(p_admin_phone text, p_admin_password text, p_driver_phone text, p_amount numeric, p_note text, p_action_key text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_id uuid;
begin
  if not public.verify_action_key(p_action_key) then
    return jsonb_build_object('ok', false, 'error', 'invalid_action_key', 'message', 'مفتاح الأمان غير صحيح');
  end if;

  if not public._check_admin(p_admin_phone, p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials', 'message', 'كلمة مرور المشرف غير صحيحة أو محاولات كتير غلط');
  end if;

  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_amount', 'message', 'مبلغ غير صالح');
  end if;
  if not exists (select 1 from public.accounts where phone = p_driver_phone and role = 'driver') then
    return jsonb_build_object('ok', false, 'error', 'driver_not_found', 'message', 'السائق غير موجود');
  end if;

  insert into public.driver_cash_reminders (driver_phone, amount, note, created_by_phone)
  values (p_driver_phone, p_amount, p_note, v_admin.phone)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;
grant execute on function public.admin_create_cash_reminder(text, text, text, numeric, text, text) to anon, authenticated;

-- 7) admin_create_promotion — app_promotions row -> jsonb{ok,error,message,promotion}
drop function if exists public.admin_create_promotion(text, text, text, text, text, text, integer, timestamp with time zone);
create or replace function public.admin_create_promotion(p_admin_phone text, p_admin_password text, p_message text, p_emoji text, p_image_url text, p_target text, p_display_seconds integer, p_ends_at timestamp with time zone)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_row public.app_promotions;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials', 'message', 'كلمة مرور المشرف غير صحيحة أو محاولات كتير غلط');
  end if;
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  if p_message is null or length(trim(p_message)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'message_required', 'message', 'لازم تكتب نص الرسالة');
  end if;
  if p_ends_at is null or p_ends_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'invalid_ends_at', 'message', 'حدد ميعاد انتهاء صحيح');
  end if;

  insert into public.app_promotions (message, emoji, image_url, target, display_seconds, ends_at, created_by)
  values (
    trim(p_message), nullif(trim(coalesce(p_emoji, '')), ''), nullif(trim(coalesce(p_image_url, '')), ''),
    coalesce(p_target, 'all'), coalesce(p_display_seconds, 8), p_ends_at, v_admin.phone
  )
  returning * into v_row;

  return jsonb_build_object('ok', true, 'promotion', to_jsonb(v_row));
end;
$$;
grant execute on function public.admin_create_promotion(text, text, text, text, text, text, integer, timestamp with time zone) to anon, authenticated;

-- 8) admin_get_account_detail — TABLE -> jsonb{ok,error,account}
drop function if exists public.admin_get_account_detail(text, text, text);
create or replace function public.admin_get_account_detail(p_admin_phone text, p_admin_password text, p_target_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_acc record;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials', 'message', 'كلمة مرور المشرف غير صحيحة أو محاولات كتير غلط');
  end if;

  select a.id, a.phone, a.name, a.role, a.city, a.email, a.username, a.status, a.created_at,
         a.national_id, a.national_id_expiry, a.avatar_url
    into v_acc
    from public.accounts a
   where a.phone in (p_target_phone,
                     case when p_target_phone like '+20%' then '0'||substr(p_target_phone,4) else p_target_phone end,
                     case when p_target_phone like '0%'   then '+2'||p_target_phone           else p_target_phone end)
   limit 1;

  return jsonb_build_object('ok', true, 'account', to_jsonb(v_acc));
end;
$$;
grant execute on function public.admin_get_account_detail(text, text, text) to anon, authenticated;

-- 9) admin_list_accounts — TABLE/SETOF -> jsonb{ok,error,rows}
drop function if exists public.admin_list_accounts(text, text, text);
create or replace function public.admin_list_accounts(p_admin_phone text, p_admin_password text, p_role text default null::text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials', 'message', 'كلمة مرور المشرف غير صحيحة أو محاولات كتير غلط');
  end if;

  select coalesce(jsonb_agg(t), '[]'::jsonb) into v_rows from (
    select a.id, a.phone, a.name, a.role, a.city, a.email, a.username, a.status, a.created_at
      from public.accounts a
     where p_role is null or a.role = p_role
     order by a.created_at desc
     limit 2000
  ) t;

  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;
grant execute on function public.admin_list_accounts(text, text, text) to anon, authenticated;

-- 10) admin_list_promotions — SETOF -> jsonb{ok,error,rows}
drop function if exists public.admin_list_promotions(text, text);
create or replace function public.admin_list_promotions(p_admin_phone text, p_admin_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows jsonb;
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials', 'message', 'كلمة مرور المشرف غير صحيحة أو محاولات كتير غلط');
  end if;

  select coalesce(jsonb_agg(t order by created_at desc), '[]'::jsonb) into v_rows
    from (select * from public.app_promotions order by created_at desc limit 200) t;

  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;
grant execute on function public.admin_list_promotions(text, text) to anon, authenticated;
