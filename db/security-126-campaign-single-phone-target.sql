-- =====================================================================
--  وصّلها — Security #126: إشعار ترويجي لرقم تليفون واحد بعينه
--
--  "📣 إشعار ترويجي جديد" في لوحة التحكم كان بيستهدف فئة كاملة بس
--  (عملاء/سائقين/تجار/الكل) — مفيش طريقة تبعت لشخص واحد بعينه من غير
--  ما تطلب كود SQL يدوي. أضفنا خيار استهداف رابع: "phone" — الحملة
--  وقتها بتحمل رقم تليفون محدد (target_phone) بدل الفئة، وservice-push
--  بتاعة send-push تستخدم نفس مسار الإرسال "شخص واحد" اللي أصلًا موجود
--  فيها (payload.phone) — مفيش تغيير في send-push نفسها.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.marketing_campaigns add column if not exists target_phone text;

alter table public.marketing_campaigns drop constraint if exists marketing_campaigns_target_role_check;
alter table public.marketing_campaigns add constraint marketing_campaigns_target_role_check
  check (target_role in ('customer', 'driver', 'merchant', 'all', 'phone'));

alter table public.marketing_campaigns drop constraint if exists marketing_campaigns_phone_target_check;
alter table public.marketing_campaigns add constraint marketing_campaigns_phone_target_check
  check (target_role <> 'phone' or target_phone is not null);

create or replace function public.admin_create_campaign(
  p_admin_phone text, p_admin_password text, p_title text, p_body text,
  p_target_role text, p_url text, p_send_at timestamptz, p_target_phone text default null
) returns boolean
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

  insert into public.marketing_campaigns (title, body, target_role, target_phone, url, send_at, created_by)
  values (trim(p_title), trim(p_body), p_target_role, nullif(trim(coalesce(p_target_phone, '')), ''),
          coalesce(nullif(trim(p_url), ''), '/'), coalesce(p_send_at, now()), v_admin.phone);
  return true;
end;
$$;
grant execute on function public.admin_create_campaign(text, text, text, text, text, text, timestamptz, text) to anon, authenticated;

create or replace function public.send_due_marketing_campaigns()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_enabled boolean;
  v_c record;
  v_role text;
begin
  select coalesce(value, 'false') = 'true' into v_enabled
  from public.app_settings where key = 'feature_marketing_campaigns_enabled';
  if not coalesce(v_enabled, true) then return; end if;

  for v_c in
    select * from public.marketing_campaigns
     where status = 'scheduled' and send_at <= now()
  loop
    update public.marketing_campaigns set status = 'sent', sent_at = now() where id = v_c.id;

    if v_c.target_role = 'phone' then
      perform net.http_post(
        url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'x-push-secret', public._push_trigger_secret(),
          'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
        ),
        body    := jsonb_build_object(
          'phone',  v_c.target_phone,
          'title',  v_c.title,
          'body',   v_c.body,
          'url',    v_c.url,
          'tag',    'wslha-campaign-' || v_c.id
        )
      );
    else
      foreach v_role in array (
        case when v_c.target_role = 'all' then array['customer', 'driver', 'merchant']
             else array[v_c.target_role] end
      )
      loop
        perform net.http_post(
          url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'x-push-secret', public._push_trigger_secret(),
            'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
          ),
          body    := jsonb_build_object(
            'target', v_role,
            'title',  v_c.title,
            'body',   v_c.body,
            'url',    v_c.url,
            'tag',    'wslha-campaign-' || v_c.id || '-' || v_role
          )
        );
      end loop;
    end if;
  end loop;
end;
$$;
