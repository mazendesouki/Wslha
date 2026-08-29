-- =====================================================================
--  وصّلها — Security #46: قفل صف المحفظة أثناء رسم نشر إعلان سوق المستعمل
--
--  guard_marketplace_item() كانت بتقرا balance بدون for update قبل ما
--  تخصم الرسم — لو نفس البائع بعت إعلانين في نفس اللحظة (استدعائين
--  متزامنين)، ممكن الاتنين يقروا نفس الرصيد الكافي قبل ما أي خصم يتسجل،
--  فيعدّي الاتنين ويوصل الرصيد لسالب بمقدار رسم واحد. إضافة for update
--  بتقفل صف المحفظة لحد ما الترانزاكشن (تريجر INSERT الكامل) يخلص، فالنداء
--  التاني بينتظر ويشوف الرصيد بعد الخصم الأول فعلاً.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.guard_marketplace_item()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_role    text;
  v_fee     numeric;
  v_balance numeric;
begin
  select role into v_role from public.accounts
   where phone in (new.seller_phone,
                   case when new.seller_phone like '+20%' then '0'||substr(new.seller_phone,4) else new.seller_phone end,
                   case when new.seller_phone like '0%'   then '+2'||new.seller_phone           else new.seller_phone end)
   limit 1;

  if v_role = 'merchant' then
    new.seller_type := 'merchant';
    if new.quantity > 500 then new.quantity := 500; end if;
  else
    new.seller_type := 'customer';
    new.quantity := 1; -- الأفراد: قطعة واحدة لكل إعلان (لا يُستخدم كمتجر مصغّر)
  end if;

  new.status := 'active';       -- النشر فوري دائماً (لا يمكن للعميل تعيين حالة مبدئية أخرى)
  new.reports_count := 0;

  -- رسم نشر الإعلان — يُخصم من محفظة البائع؛ لو الرصيد مايكفيش، الإعلان
  -- ماينشرش خالص (بلا خصم جزئي أو دين). for update يقفل صف المحفظة لحد ما
  -- الإدراج ده يخلص، فمينفعش استدعائين متزامنين يقروا نفس الرصيد ويعدّوا
  -- الاتنين قبل أي خصم (security-46).
  v_fee := public._pricing_setting_num('marketplace_listing_fee', 5, 0);
  if v_fee > 0 then
    select balance into v_balance from public.wallets where phone = new.seller_phone for update;
    v_balance := coalesce(v_balance, 0);
    if v_balance < v_fee then
      raise exception 'insufficient_wallet_balance:needs=%:has=%', v_fee, v_balance;
    end if;
    perform public.add_wallet_balance(new.seller_phone, -v_fee);
    insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
    values (
      'wtx-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
      new.seller_phone, -v_fee, 'marketplace_fee', new.id,
      'رسم نشر إعلان في سوق المستعمل', now()
    );
  end if;

  return new;
end;
$$;
