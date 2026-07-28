-- =====================================================================
--  وصّلها — Security #6: خدمة "دليفري" العامة (أي مستخدم، أي مكان)
--
--  خدمة منفصلة تمامًا عن توصيل التجار (security-05): أي مستخدم مسجّل
--  يقدر يطلب شراء/توصيل من أي متجر أو مكان مش مسجّل على المنصة، ولأي
--  عنوان. تستخدم نفس أعمدة orders اللي أُضيفت في security-05
--  (source, direction, service_fee) — لا حاجة لأعمدة جديدة، فقط قيمة
--  source مختلفة ('general_delivery') لتمييزها في لوحة الأدمن، ورسوم
--  خدمة قابلة للتعديل بشكل مستقل عن رسوم توصيل التجار.
--
--  Run once in the Supabase SQL Editor. Idempotent — safe to re-run.
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value)
values ('general_delivery_service_fee', '10')
on conflict (key) do nothing;
