-- =====================================================================
--  وصّلها — Security #68: نظام الطوارئ (SOS) — جهات اتصال + سجل تنبيهات
--
--  زرار طوارئ يظهر للعميل والسائق أثناء الرحلة: يسجّل تنبيه في سجل
--  دائم (sos_alerts، يشوفه الأدمن لاحقًا) ويجهّز رسالة SMS واحدة
--  (موقع حي + رابط متابعة الرحلة نفسه المستخدم في ميزة "مشاركة
--  الرحلة"، security-65 ride-track.astro) لكل جهات اتصال الطوارئ
--  المحفوظة (emergency_contacts، حتى 3 لكل حساب) — الإرسال الفعلي
--  بيد المستخدم نفسه (فتح تطبيق الرسائل جاهز، هو بس يضغط إرسال)
--  لأن لا Android ولا iOS يسمحوا لتطبيق تالت بإرسال SMS صامت.
--
--  زي كل الجداول الحساسة التانية في المشروع: مفيش SELECT/UPDATE/DELETE
--  مباشر لـ anon/authenticated — كل حاجة عن طريق دوال security definer
--  محصورة بنفس رقم الموبايل صاحب الطلب.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create table if not exists public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  owner_phone text not null,
  contact_name text not null,
  contact_phone text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_emergency_contacts_owner on public.emergency_contacts(owner_phone);
alter table public.emergency_contacts enable row level security;
revoke all on public.emergency_contacts from anon, authenticated;

create table if not exists public.sos_alerts (
  id uuid primary key default gen_random_uuid(),
  triggered_by_phone text not null,
  triggered_by_role text,
  ride_id uuid,
  lat double precision,
  lng double precision,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists idx_sos_alerts_created on public.sos_alerts(created_at desc);
alter table public.sos_alerts enable row level security;
revoke all on public.sos_alerts from anon, authenticated;

create or replace function public.list_emergency_contacts(p_phone text)
returns setof public.emergency_contacts
language sql
security definer
set search_path = public, extensions
as $$
  select * from public.emergency_contacts where owner_phone = p_phone order by created_at asc;
$$;

create or replace function public.add_emergency_contact(p_phone text, p_name text, p_contact_phone text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
  v_count int;
begin
  select count(*) into v_count from public.emergency_contacts where owner_phone = p_phone;
  if v_count >= 3 then
    raise exception 'MAX_CONTACTS';
  end if;
  insert into public.emergency_contacts(owner_phone, contact_name, contact_phone)
  values (p_phone, trim(p_name), trim(p_contact_phone))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.delete_emergency_contact(p_id uuid, p_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  delete from public.emergency_contacts where id = p_id and owner_phone = p_phone;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

create or replace function public.log_sos_alert(
  p_phone text, p_role text, p_ride_id uuid default null,
  p_lat double precision default null, p_lng double precision default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_id uuid;
begin
  insert into public.sos_alerts(triggered_by_phone, triggered_by_role, ride_id, lat, lng, notes)
  values (p_phone, p_role, p_ride_id, p_lat, p_lng, p_notes)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.list_emergency_contacts(text) to anon, authenticated;
grant execute on function public.add_emergency_contact(text, text, text) to anon, authenticated;
grant execute on function public.delete_emergency_contact(uuid, text) to anon, authenticated;
grant execute on function public.log_sos_alert(text, text, uuid, double precision, double precision, text) to anon, authenticated;
