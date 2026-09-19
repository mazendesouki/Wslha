-- =====================================================================
--  وصّلها — Security #74: بوت الذكاء الاصطناعي للدعم الفني
--
--  رد تلقائي فوري على العميل/السائق من ذكاء اصطناعي (Claude — Anthropic)
--  لحد ما موظف حقيقي يدخل المحادثة، فبعدها البوت بيسكت تلقائيًا.
--
--  التغييرات:
--   1) support_messages.sender_role يقبل 'ai' كمان (بجانب user/support).
--   2) support_conversations.ai_enabled — لما يبقى true البوت شغال على
--      المحادثة دي؛ بيتقفل تلقائيًا (false) أول ما أدمن حقيقي يرد
--      (admin_send_support_reply)، عشان الرد الآلي ما يتعارضش مع رد
--      موظف حقيقي.
--   3) مفتاح Anthropic API نفسه مش هنا خالص — ده Secret على Edge
--      Function اسمها ai-support-reply (supabase/functions)، مش بيتخزن
--      في قاعدة البيانات ولا في كود التطبيق أبدًا.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

alter table public.support_messages drop constraint if exists support_messages_sender_role_check;
alter table public.support_messages add constraint support_messages_sender_role_check
  check (sender_role in ('user', 'support', 'ai'));

alter table public.support_conversations add column if not exists ai_enabled boolean not null default true;

-- الأدمن بيرد يدوي → يقفل البوت على المحادثة دي تلقائيًا.
create or replace function public.admin_send_support_reply(p_admin_phone text, p_admin_password text, p_conversation_id uuid, p_body text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if p_body is null or length(trim(p_body)) = 0 then return false; end if;

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

  update public.support_conversations set updated_at = now(), ai_enabled = false where id = p_conversation_id;
  insert into public.support_messages (conversation_id, sender_role, body, read_by_admin)
    values (p_conversation_id, 'support', trim(p_body), true);
  return true;
end;
$$;
grant execute on function public.admin_send_support_reply(text, text, uuid, text) to anon, authenticated;

-- تشغيل بوت الرد الآلي افتراضيًا — قابل للإيقاف من لوحة التحكم فورًا.
insert into public.app_settings (key, value) values
  ('feature_ai_bot_enabled', 'true')
on conflict (key) do nothing;
