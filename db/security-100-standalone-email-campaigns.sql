-- ═══════════════════════════════════════════════════════════════
-- Replaces security-99's "send_email checkbox bolted onto the push
-- campaign form" with a fully independent email-campaign tool, per
-- explicit request — push notifications and marketing emails are
-- separate channels with separate timing/content needs, not one
-- campaign wearing two hats.
--
-- email_campaigns mirrors marketing_campaigns' shape (subject/body/
-- target_role/send_at/status) but is its own table with its own admin_*
-- RPCs and its own pg_cron job — reuses the send-marketing-email edge
-- function built for security-99 (that part of the backend was already
-- correct and tested live; only the "how it's triggered/managed"
-- changes here).
-- ═══════════════════════════════════════════════════════════════
set search_path = public, extensions;

create table if not exists public.email_campaigns (
  id uuid primary key default gen_random_uuid(),
  subject text not null,
  body text not null,
  target_role text not null check (target_role in ('customer', 'driver', 'merchant', 'all')),
  send_at timestamptz not null default now(),
  status text not null default 'scheduled' check (status in ('scheduled', 'sent', 'cancelled')),
  sent_at timestamptz,
  created_by text,
  created_at timestamptz not null default now()
);
alter table public.email_campaigns enable row level security;
revoke all on public.email_campaigns from anon, authenticated;

create or replace function public.admin_create_email_campaign(
  p_admin_phone text, p_admin_password text, p_subject text, p_body text,
  p_target_role text, p_send_at timestamptz
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

  insert into public.email_campaigns (subject, body, target_role, send_at, created_by)
  values (trim(p_subject), trim(p_body), p_target_role, coalesce(p_send_at, now()), v_admin.phone);
  return true;
end;
$$;
grant execute on function public.admin_create_email_campaign(text, text, text, text, text, timestamptz) to anon, authenticated;

create or replace function public.admin_list_email_campaigns(p_admin_phone text, p_admin_password text)
returns setof public.email_campaigns
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

  return query select * from public.email_campaigns order by send_at desc limit 300;
end;
$$;
grant execute on function public.admin_list_email_campaigns(text, text) to anon, authenticated;

create or replace function public.admin_cancel_email_campaign(p_admin_phone text, p_admin_password text, p_campaign_id uuid)
returns boolean
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
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;

  update public.email_campaigns set status = 'cancelled'
   where id = p_campaign_id and status = 'scheduled';
  return true;
end;
$$;
grant execute on function public.admin_cancel_email_campaign(text, text, uuid) to anon, authenticated;

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
        'target',  v_c.target_role,
        'subject', v_c.subject,
        'body',    v_c.body
      )
    );
  end loop;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'send-email-campaigns';
select cron.schedule('send-email-campaigns', '* * * * *', $$select public.send_due_email_campaigns();$$);
