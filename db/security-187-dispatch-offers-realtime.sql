-- security-187: driver offer poll → realtime
-- آمن لإعادة التشغيل (idempotent) — safe to re-run.
--
-- The driver app polled dispatch_offers every 5 seconds because offers
-- expire in 25 seconds, so a slower poll risked a driver seeing an offer
-- with too little time left to respond (or missing it entirely). This
-- adds a realtime channel for the fast path and keeps a slower safety-net
-- poll for resilience if the realtime connection drops.
--
-- Scope: SELECT only, and only pending rows — a driver only ever needs
-- to see currently-live offers, never accepted/rejected/expired history.
-- Same permissive-SELECT-policy pattern already used for rides,
-- driver_locations, and ride_messages' realtime access.

alter table public.dispatch_offers enable row level security;

drop policy if exists dispatch_offers_select_pending on public.dispatch_offers;
create policy dispatch_offers_select_pending
  on public.dispatch_offers for select
  using (status = 'pending');

grant select on public.dispatch_offers to anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'dispatch_offers'
  ) then
    alter publication supabase_realtime add table public.dispatch_offers;
  end if;
end $$;
