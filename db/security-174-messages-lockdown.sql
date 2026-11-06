-- =====================================================================
--  وصّلها — Security #174: قفل جدول messages المفتوح بالكامل
--
--  اتكشف ضمن مراجعة لوحة الأدمن إن messages (رسائل نموذج "تواصل معنا")
--  عندها RLS policies مفتوحة بالكامل لـ public على SELECT وUPDATE
--  (allow_anon_select_messages, allow_anon_update_messages — qual=true)
--  — نفس فئة مشكلة stores/orders/rides (security-171/172/173)، بس هنا
--  التسريب أخطر لأنه بيانات شخصية مباشرة (اسم/تليفون/إيميل) مبعوتة من
--  نموذج عام، مش بيانات تشغيلية. admin.astro's updateMsgStatus() كانت
--  كمان بتعمل PATCH مباشر من غير المرور حتى بـ getAdminPass() الخاص
--  بالصفحة (سبق الهيلبرز اللي اتصلحت في security-170).
--
--  الـ INSERT فضل مفتوح عمدًا — نموذج "تواصل معنا" (contact.astro) لازم
--  يبعت رسالة من غير تسجيل دخول، ومفيش بيانات موجودة ممكن تتبهدل
--  (أسوأ حالة رسالة وهمية، زي أي سبام ممكن يحصل في أي نموذج تواصل).
--
--  دالتين جداد، نفس نمط _check_admin المستخدم في كل دوال الأدمن التانية:
--    • admin_list_messages: بترجع الرسائل (مع فلتر status اختياري)،
--      بترجع صفوف فاضية (مش exception) لو كلمة المرور غلط — نفس نمط
--      أمان الـ sentinel-return بتاع security-158.
--    • admin_update_message_status: بتعدّل status بس لصف واحد بالـ id.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.admin_list_messages(
  p_admin_phone text, p_admin_password text, p_status_filter text default null
)
returns setof public.messages
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then
    return;
  end if;
  return query
    select * from public.messages
     where p_status_filter is null or status = p_status_filter
     order by created_at desc;
end;
$$;
grant execute on function public.admin_list_messages(text, text, text) to anon, authenticated;

create or replace function public.admin_update_message_status(
  p_admin_phone text, p_admin_password text, p_message_id text, p_status text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public._check_admin(p_admin_phone, p_admin_password) then return false; end if;
  update public.messages set status = p_status where id = p_message_id;
  return found;
end;
$$;
grant execute on function public.admin_update_message_status(text, text, text, text) to anon, authenticated;

-- سحب القراءة/التعديل المباشر — أي قراءة أو تعديل دلوقتي لازم يعدي من
-- الدوال فوق. الـ INSERT فضل مفتوح عمدًا (نموذج "تواصل معنا").
drop policy if exists "allow_anon_select_messages" on public.messages;
drop policy if exists "allow_anon_update_messages" on public.messages;
revoke select, update, delete on public.messages from anon, authenticated;
