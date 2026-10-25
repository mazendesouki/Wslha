-- =====================================================================
--  وصّلها — Security #129: سد ثغرة تجاوز الفحص عبر الإدخال المباشر
--
--  security-127 أضاف فحص is_service_active() لخدمتي "السوق المستعمل"
--  و"إيداع المحفظة"، لكن الفحص كان جوه RPC واحد بس لكل خدمة
--  (request_marketplace_delivery و request_deposit على التوالي) —
--  مش trigger مستقل على الجدول زي باقي الخدمات (الرحلات، الطلبات،
--  عقود الشركات، تسجيل السائقين/التجار).
--
--  المشكلة: المستخدم anon عنده صلاحية INSERT مباشرة على:
--    - public.wallet_requests  (تقدر تضيف صف إيداع من غير ما تمر
--      على request_deposit() خالص — مثلاً لو تطبيق قديم لسه بيعمل
--      insert مباشر بدل ما ينادي الـ RPC، أو أي استدعاء REST مباشر)
--    - public.marketplace_items (تقدر تنشر إعلان جديد من غير ما تمر
--      على أي فحص خدمة أصلًا — الفحص في request_marketplace_delivery
--      بيتحقق بس وقت الشراء، مش وقت النشر)
--
--  الحل: نفس نمط security-127 — trigger مستقل قبل الإدخال على الجدول
--  نفسه، منفصل عن أي منطق موجود، عشان يقفل أي طريق تاني للإدخال مهما
--  كانت نسخة التطبيق أو طريقة الاستدعاء.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- 1) wallet_requests — يقفل بس صفوف الإيداع (kind = 'deposit')، مش
--    السحب (ده مش جزء من خدمة "إيداع المحفظة").
create or replace function public._guard_wallet_deposit_service_control()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.kind = 'deposit' and not public.is_service_active('wallet_deposit') then
    raise exception 'service_unavailable: wallet_deposit';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_wallet_deposit_service_control on public.wallet_requests;
create trigger trg_guard_wallet_deposit_service_control
  before insert on public.wallet_requests
  for each row execute function public._guard_wallet_deposit_service_control();

-- 2) marketplace_items — يقفل نشر إعلان جديد (الشراء أصلًا متفحوص
--    جوه request_marketplace_delivery).
create or replace function public._guard_marketplace_listing_service_control()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.is_service_active('marketplace') then
    raise exception 'service_unavailable: marketplace';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_marketplace_listing_service_control on public.marketplace_items;
create trigger trg_guard_marketplace_listing_service_control
  before insert on public.marketplace_items
  for each row execute function public._guard_marketplace_listing_service_control();
