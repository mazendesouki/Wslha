-- =====================================================================
--  وصّلها — Security #84: إشعار Push للعميل عند رد الدعم الفني/البوت
--
--  admin_send_support_reply كانت بتسجّل رد الموظف بس، من غير أي تنبيه
--  للعميل لو مش فاتح شاشة الشات فعليًا (Realtime بديل بالـ polling هنا
--  أصلاً — security-73 — فمفيش حتى تحديث لحظي لو الشاشة مقفولة).
--  نفس الموضوع لرد بوت الذكاء الاصطناعي (Edge Function منفصلة). دلوقتي
--  الاتنين بيبعتوا push للعميل "🎧 رد جديد من الدعم الفني".
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.admin_send_support_reply(p_admin_phone text, p_admin_password text, p_conversation_id uuid, p_body text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_customer_phone text;
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
grant execute on function public.admin_send_support_reply(text, text, uuid, text) to anon, authenticated;
