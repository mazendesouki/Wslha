-- ═══════════════════════════════════════════════════════════════
-- Server-side enforcement for the distance-based delivery fee across
-- all three courier-style flows: general delivery (delivery.astro),
-- merchant delivery (merchant-delivery.astro), and courier.astro. Same
-- idea as security-12 for the flat service fee, but this one recomputes
-- delivery_fee from the stored pickup/dropoff coordinates instead of
-- trusting the client's distance × formula math — store_lat/store_lng/
-- customer_lat/customer_lng are already saved on every order from these
-- three pages, so the server can derive the same haversine×1.35 "road"
-- distance the client used and re-run the exact fee formula
-- (deliveryFeeFor()/feeFor() in those pages: base + max(0,km-3)×3,
-- rounded up to 5) — no separate distance_km column needed.
--
-- courier.astro's base fee depends on package size (📄 مستند=25 / صغير=30
-- / متوسط=40 / كبير=55), which wasn't previously stored as its own
-- column — only baked into a free-text label. Added `package_size` here
-- and courier.astro now sends it, so the server can look up the right
-- base instead of guessing from text.
--
-- Runs alongside security-12's trg_guard_order_service_fee — Postgres
-- fires same-event BEFORE triggers in alphabetical order by name, so
-- trg_guard_order_delivery_fee ('d') runs before
-- trg_guard_order_service_fee ('s'); the service-fee trigger's `total`
-- recompute (which reads NEW.delivery_fee) therefore always sees this
-- trigger's corrected value, regardless of statement order.
-- ═══════════════════════════════════════════════════════════════

alter table public.orders add column if not exists package_size text;

create or replace function public.guard_order_delivery_fee()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_km   numeric;
  v_base numeric;
  v_fee  numeric;
begin
  if not (new.source in ('general_delivery', 'merchant_delivery') or new.store_id = 'courier') then
    return new; -- not one of the three distance-fee-driven flows
  end if;

  if new.store_lat is null or new.store_lng is null or new.customer_lat is null or new.customer_lng is null then
    return new; -- missing coordinates — can't verify, leave the submitted value
  end if;

  v_km := 1.35 * (
    6371 * 2 * asin(least(1, sqrt(
      power(sin(radians(new.customer_lat - new.store_lat) / 2), 2) +
      cos(radians(new.store_lat)) * cos(radians(new.customer_lat)) *
      power(sin(radians(new.customer_lng - new.store_lng) / 2), 2)
    )))
  );

  if new.store_id = 'courier' then
    v_base := case new.package_size
      when 'small'  then 30
      when 'medium' then 40
      when 'large'  then 55
      else 25 -- 'doc' or unset
    end;
  else
    v_base := 30;
  end if;

  v_fee := ceil((v_base + greatest(v_km - 3, 0) * 3) / 5) * 5;
  new.delivery_fee := v_fee;
  new.total := coalesce(new.subtotal, 0) + coalesce(new.service_fee, 0) + v_fee;
  return new;
end;
$$;

drop trigger if exists trg_guard_order_delivery_fee on public.orders;
create trigger trg_guard_order_delivery_fee
before insert on public.orders
for each row execute function public.guard_order_delivery_fee();
