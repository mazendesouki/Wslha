-- =====================================================================
--  وصّلها — Security #79: إشعارات ترويجية/تسويقية مجدولة
--
--  الأدمن يكتب إشعار (عنوان + نص + رابط اختياري) ويحدد الفئة المستهدفة
--  (عملاء/سائقين/تجار/الكل) ويختار يبعته فورًا أو في ميعاد لاحق. الإرسال
--  الفعلي بيتم عن طريق نفس Edge Function الموجودة (send-push) اللي كل
--  إشعارات المشروع بتعدي عليها بالفعل.
--
--  جدول marketing_campaigns بدون أي قراءة/كتابة مباشرة — زي كل جدول
--  حساس تاني، كل حاجة عن طريق دوال محكومة بباسورد الأدمن (زي
--  admin_list_accounts). الإرسال نفسه بيحصل من Job مجدول بـ pg_cron
--  (كل دقيقة) بيدوّر على أي حملة send_at بتاعها وصل ولسه status
--  'scheduled'.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.marketing_campaigns (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  target_role text not null check (target_role in ('customer', 'driver', 'merchant', 'all')),
  url text not null default '/',
  send_at timestamptz not null default now(),
  status text not null default 'scheduled' check (status in ('scheduled', 'sent', 'cancelled')),
  sent_at timestamptz,
  created_by text,
  created_at timestamptz not null default now()
);

alter table public.marketing_campaigns enable row level security;
revoke all on public.marketing_campaigns from anon, authenticated;

insert into public.app_settings (key, value) values
  ('feature_marketing_campaigns_enabled', 'true')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- دوال الأدمن — بباسورد زي admin_list_accounts.
-- ---------------------------------------------------------------------
create or replace function public.admin_create_campaign(
  p_admin_phone text, p_admin_password text, p_title text, p_body text,
  p_target_role text, p_url text, p_send_at timestamptz
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

  insert into public.marketing_campaigns (title, body, target_role, url, send_at, created_by)
  values (trim(p_title), trim(p_body), p_target_role, coalesce(nullif(trim(p_url), ''), '/'),
          coalesce(p_send_at, now()), v_admin.phone);
  return true;
end;
$$;
grant execute on function public.admin_create_campaign(text, text, text, text, text, text, timestamptz) to anon, authenticated;

create or replace function public.admin_list_campaigns(p_admin_phone text, p_admin_password text)
returns setof public.marketing_campaigns
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

  return query select * from public.marketing_campaigns order by send_at desc limit 300;
end;
$$;
grant execute on function public.admin_list_campaigns(text, text) to anon, authenticated;

create or replace function public.admin_cancel_campaign(p_admin_phone text, p_admin_password text, p_campaign_id uuid)
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

  update public.marketing_campaigns set status = 'cancelled'
   where id = p_campaign_id and status = 'scheduled';
  return true;
end;
$$;
grant execute on function public.admin_cancel_campaign(text, text, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- الإرسال الفعلي — Job مجدول كل دقيقة.
-- ---------------------------------------------------------------------
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
    end loop;
  end loop;
end;
$$;

select cron.unschedule(jobid) from cron.job where jobname = 'send-marketing-campaigns';
select cron.schedule('send-marketing-campaigns', '* * * * *', $$select public.send_due_marketing_campaigns();$$);
