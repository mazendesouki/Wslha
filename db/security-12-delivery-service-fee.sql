-- ═══════════════════════════════════════════════════════════════
-- Server-side enforcement for the delivery service fee — same gap as
-- airport rides had before AIRPORT_MIN_FARE: delivery.astro and
-- merchant-delivery.astro read general_delivery_service_fee /
-- merchant_delivery_service_fee from app_settings client-side, then
-- insert whatever number they computed directly into orders.service_fee
-- (and orders.total) — nothing on the server re-checks it, so a
-- tampered client could send service_fee=0.
--
-- This adds a BEFORE INSERT trigger on `orders`, scoped to exactly the
-- two order sources these two pages set (`source = 'general_delivery'`
-- or `'merchant_delivery'`) — regular store orders never set `source`,
-- so they pass through untouched. Reuses the
-- public._pricing_setting_num() helper from
-- security-11-pricing-settings.sql.
--
-- NOT covered here: `delivery_fee` (the distance-based courier fee —
-- deliveryFeeFor() in both pages, and feeFor() in courier.astro, none
-- of which read app_settings; they're hardcoded per-page formulas, a
-- separate piece of work from "trip pricing"), and `subtotal` (an
-- arbitrary purchase amount the requester types in for products bought
-- elsewhere — not something the server can independently verify).
-- ═══════════════════════════════════════════════════════════════

create or replace function public.guard_order_service_fee()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_key text;
  v_fee numeric;
begin
  if new.source = 'general_delivery' then
    v_key := 'general_delivery_service_fee';
  elsif new.source = 'merchant_delivery' then
    v_key := 'merchant_delivery_service_fee';
  else
    return new; -- not one of the two app_settings-driven delivery flows
  end if;

  v_fee := public._pricing_setting_num(v_key, 10, 0);
  new.service_fee := v_fee;
  new.total := coalesce(new.subtotal, 0) + v_fee + coalesce(new.delivery_fee, 0);
  return new;
end;
$$;

drop trigger if exists trg_guard_order_service_fee on public.orders;
create trigger trg_guard_order_service_fee
before insert on public.orders
for each row execute function public.guard_order_service_fee();
