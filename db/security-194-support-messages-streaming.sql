-- security-194: realtime support for streamed AI support replies
-- آمن لإعادة التشغيل (idempotent) — safe to re-run.
--
-- ai-support-reply used to wait for Claude's full response before saving
-- and pushing it — the chat showed nothing until the entire reply had
-- landed. This adds a `streaming` flag so the edge function can insert a
-- growing placeholder row and update it as tokens arrive, with the
-- client watching it live via Realtime instead of the existing 10s poll
-- — same permissive-SELECT-policy pattern already used for rides,
-- driver_locations, ride_messages, and dispatch_offers realtime access.

alter table public.support_messages add column if not exists streaming boolean not null default false;

alter table public.support_messages enable row level security;

drop policy if exists support_messages_select_all on public.support_messages;
create policy support_messages_select_all
  on public.support_messages for select
  using (true);

grant select on public.support_messages to anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'support_messages'
  ) then
    alter publication supabase_realtime add table public.support_messages;
  end if;
end $$;
