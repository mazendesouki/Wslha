-- ═══════════════════════════════════════════════════════════════
-- Adds support for sending an email campaign to arbitrary email
-- addresses too — not just accounts already registered in the app
-- (customer/driver/merchant) — for broader brand-awareness outreach
-- (prospects, partners, a collected list), on top of the existing
-- role-based targeting.
--
-- Verified live: sent to target='customer' with extra_emails containing
-- an unregistered address — both the registered customer's email and
-- the extra address received the campaign in the same batch call.
-- ═══════════════════════════════════════════════════════════════
set search_path = public, extensions;

alter table public.email_campaigns add column if not exists extra_emails text[];

create or replace function public.admin_create_email_campaign(
  p_admin_phone text, p_admin_password text, p_subject text, p_body text,
  p_target_role text, p_send_at timestamptz, p_image_url text default null,
  p_extra_emails text[] default null
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_subject is null or length(trim(p_subject)) = 0 or p_body is null or length(trim(p_body)) = 0 then
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

  insert into public.email_campaigns (subject, body, target_role, send_at, created_by, image_url, extra_emails)
  values (trim(p_subject), trim(p_body), p_target_role, coalesce(p_send_at, now()), v_admin.phone,
          nullif(trim(coalesce(p_image_url, '')), ''), p_extra_emails);
  return true;
end;
$$;
grant execute on function public.admin_create_email_campaign(text, text, text, text, text, timestamptz, text, text[]) to anon, authenticated;

create or replace function public.send_due_email_campaigns()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_c record;
begin
  for v_c in
    select * from public.email_campaigns
     where status = 'scheduled' and send_at <= now()
  loop
    update public.email_campaigns set status = 'sent', sent_at = now() where id = v_c.id;

    perform net.http_post(
      url     := 'https://vtikgyiopkjnrwlqnmfx.supabase.co/functions/v1/send-marketing-email',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-push-secret', public._push_trigger_secret(),
        'apikey',        'sb_publishable_PLSnpvCT-sAyUMtymNgTwA_QmL2suw4'
      ),
      body    := jsonb_build_object(
        'target',       v_c.target_role,
        'subject',      v_c.subject,
        'body',         v_c.body,
        'image_url',    v_c.image_url,
        'extra_emails', to_jsonb(v_c.extra_emails)
      )
    );
  end loop;
end;
$$;
