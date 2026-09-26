-- ═══════════════════════════════════════════════════════════════
-- Extends the existing push-notification "marketing campaigns" tool
-- (security-79) with an email channel — same admin form, an extra
-- checkbox. Requested specifically to also help build wslha.co's fresh
-- sending domain reputation with Gmail through legitimate, wanted
-- correspondence (rather than test-only sends).
--
-- send_due_marketing_campaigns() (the existing every-minute pg_cron job)
-- now ALSO calls a new send-marketing-email edge function per target
-- role when send_email = true, alongside its existing send-push call —
-- same x-push-secret auth pattern, reusing accounts.email (now that
-- driver/merchant registration collects one too, per the earlier fix).
--
-- Verified live: called send-marketing-email directly via net.http_post
-- with target='customer' — email delivered per Resend (subject "اختبار
-- أداة الحملات البريدية").
-- ═══════════════════════════════════════════════════════════════
set search_path = public, extensions;

alter table public.marketing_campaigns add column if not exists send_email boolean not null default false;

create or replace function public.admin_create_campaign(
  p_admin_phone text, p_admin_password text, p_title text, p_body text,
  p_target_role text, p_url text, p_send_at timestamptz, p_send_email boolean default false
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

  insert into public.marketing_campaigns (title, body, target_role, url, send_at, created_by, send_email)
  values (trim(p_title), trim(p_body), p_target_role, coalesce(nullif(trim(p_url), ''), '/'),
          coalesce(p_send_at, now()), v_admin.phone, coalesce(p_send_email, false));
  return true;
end;
$$;
grant execute on function public.admin_create_campaign(text, text, text, text, text, text, timestamptz, boolean) to anon, authenticated;

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

      if v_c.send_email then
        perform net.http_post(
          url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-marketing-email',
          headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'x-push-secret', public._push_trigger_secret(),
            'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
          ),
          body    := jsonb_build_object(
            'target',  v_role,
            'subject', v_c.title,
            'body',    v_c.body
          )
        );
      end if;
    end loop;
  end loop;
end;
$$;
