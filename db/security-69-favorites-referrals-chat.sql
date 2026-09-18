-- =====================================================================
--  وصّلها — Security #69: سائقين مفضّلين + كود دعوة (إحالة) + دردشة الرحلة
--
--  ثلاث ميزات مستقلة، نفس نمط الحماية المتبع طول الجلسة دي: لا SELECT
--  ولا INSERT/UPDATE/DELETE مباشر لـ anon/authenticated على أي جدول
--  جديد إلا لو مذكور صراحة، كل الوصول عن طريق دوال security definer
--  محصورة برقم موبايل الطالب.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) سائقين مفضّلين
-- ---------------------------------------------------------------------
create table if not exists public.favorite_drivers (
  id uuid primary key default gen_random_uuid(),
  customer_phone text not null,
  driver_phone text not null,
  created_at timestamptz not null default now(),
  unique (customer_phone, driver_phone)
);
create index if not exists idx_favorite_drivers_customer on public.favorite_drivers(customer_phone);
alter table public.favorite_drivers enable row level security;
revoke all on public.favorite_drivers from anon, authenticated;

create or replace function public.list_favorite_drivers(p_phone text)
returns table(driver_phone text, driver_name text, created_at timestamptz)
language sql
security definer
set search_path = public, extensions
as $$
  select fd.driver_phone,
         coalesce(da.full_name, '') as driver_name,
         fd.created_at
  from public.favorite_drivers fd
  left join lateral (
    select full_name from public.driver_applications
    where phone = fd.driver_phone and status = 'approved'
    order by created_at desc limit 1
  ) da on true
  where fd.customer_phone = p_phone
  order by fd.created_at desc;
$$;

-- Returns true = now favorited, false = now removed.
create or replace function public.toggle_favorite_driver(p_phone text, p_driver_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_exists boolean;
begin
  select exists(select 1 from public.favorite_drivers where customer_phone = p_phone and driver_phone = p_driver_phone) into v_exists;
  if v_exists then
    delete from public.favorite_drivers where customer_phone = p_phone and driver_phone = p_driver_phone;
    return false;
  else
    insert into public.favorite_drivers(customer_phone, driver_phone) values (p_phone, p_driver_phone)
    on conflict do nothing;
    return true;
  end if;
end;
$$;

create or replace function public.is_favorite_driver(p_phone text, p_driver_phone text)
returns boolean
language sql
security definer
set search_path = public, extensions
as $$
  select exists(select 1 from public.favorite_drivers where customer_phone = p_phone and driver_phone = p_driver_phone);
$$;

grant execute on function public.list_favorite_drivers(text) to anon, authenticated;
grant execute on function public.toggle_favorite_driver(text, text) to anon, authenticated;
grant execute on function public.is_favorite_driver(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) كود دعوة (إحالة) — كل حساب له كود فريد، أي حساب تاني يستخدمه
--    مرة واحدة بس، والاتنين ياخدوا رصيد محفظة.
-- ---------------------------------------------------------------------
alter table public.accounts add column if not exists referral_code text;
alter table public.accounts add column if not exists referred_by text;

create or replace function public.generate_referral_code()
returns text
language plpgsql
as $$
declare v_code text;
begin
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.accounts where referral_code = v_code);
  end loop;
  return v_code;
end;
$$;

update public.accounts set referral_code = public.generate_referral_code() where referral_code is null;

create unique index if not exists idx_accounts_referral_code on public.accounts(referral_code);

create or replace function public.set_referral_code_on_insert()
returns trigger
language plpgsql
as $$
begin
  if new.referral_code is null then
    new.referral_code := public.generate_referral_code();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_referral_code on public.accounts;
create trigger trg_set_referral_code
before insert on public.accounts
for each row execute function public.set_referral_code_on_insert();

create or replace function public.get_my_referral_code(p_phone text)
returns text
language sql
security definer
set search_path = public, extensions
as $$
  select referral_code from public.accounts where phone = p_phone limit 1;
$$;

-- Returns true on a successful first-time redemption, false otherwise
-- (unknown code, self-redemption, or this phone already redeemed one).
create or replace function public.redeem_referral_code(p_phone text, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner_phone text;
  v_already text;
  v_reward numeric := 20;
  v_tx_id text;
begin
  select phone into v_owner_phone from public.accounts where referral_code = upper(trim(p_code)) limit 1;
  if v_owner_phone is null or v_owner_phone = p_phone then
    return false;
  end if;

  select referred_by into v_already from public.accounts where phone = p_phone;
  if v_already is not null then
    return false;
  end if;

  update public.accounts set referred_by = v_owner_phone where phone = p_phone;

  v_tx_id := 'ref-cr-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6);
  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values (v_tx_id, p_phone, v_reward, 'referral_credit', 'مكافأة استخدام كود دعوة', now());
  perform public.add_wallet_balance(p_phone, v_reward);

  v_tx_id := 'ref-cr-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6) || '-o';
  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values (v_tx_id, v_owner_phone, v_reward, 'referral_credit', 'مكافأة دعوة صديق جديد', now());
  perform public.add_wallet_balance(v_owner_phone, v_reward);

  return true;
end;
$$;

grant execute on function public.get_my_referral_code(text) to anon, authenticated;
grant execute on function public.redeem_referral_code(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) دردشة الرحلة — رسائل نصية بين العميل والسائق أثناء رحلة معيّنة.
--    مقروءة مباشرة (USING(true), زي rides/driver_locations بالظبط —
--    نفس نموذج الثقة اللي ride-track.astro أصلاً بيعتمد عليه: امتلاك
--    الـ ride_id UUID هو حد الوصول) عشان Realtime يشتغل عليها مباشرة،
--    لكن الكتابة عن طريق send_ride_message() بس، اللي بيتحقق إن
--    المرسل طرف فعلي في نفس الرحلة قبل ما يسجّل الرسالة.
-- ---------------------------------------------------------------------
create table if not exists public.ride_messages (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null,
  sender_phone text not null,
  sender_role text not null,
  body text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_ride_messages_ride on public.ride_messages(ride_id, created_at);
alter table public.ride_messages enable row level security;

drop policy if exists ride_messages_select_open on public.ride_messages;
create policy ride_messages_select_open on public.ride_messages for select using (true);

revoke insert, update, delete on public.ride_messages from anon, authenticated;
grant select on public.ride_messages to anon, authenticated;

create or replace function public.send_ride_message(p_ride_id uuid, p_sender_phone text, p_sender_role text, p_body text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
  v_ok boolean;
  v_body text := trim(p_body);
begin
  if v_body is null or length(v_body) = 0 then
    return null;
  end if;

  select exists(
    select 1 from public.rides
    where id = p_ride_id
      and (customer_phone = p_sender_phone or driver_phone = p_sender_phone)
  ) into v_ok;
  if not v_ok then
    raise exception 'NOT_PARTICIPANT';
  end if;

  insert into public.ride_messages(ride_id, sender_phone, sender_role, body)
  values (p_ride_id, p_sender_phone, p_sender_role, v_body)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.send_ride_message(uuid, text, text, text) to anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'ride_messages'
  ) then
    alter publication supabase_realtime add table public.ride_messages;
  end if;
end $$;
