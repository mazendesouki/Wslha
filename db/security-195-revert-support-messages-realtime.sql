-- security-195: revert the open SELECT grant security-194 just added to
-- support_messages — this was a mistake, caught immediately.
-- آمن لإعادة التشغيل (idempotent) — safe to re-run.
--
-- security-69 (the original migration that created this table) explicitly
-- left support_messages WITHOUT a direct SELECT grant on purpose: unlike
-- ride_messages (ride-scoped, lower stakes), support chats can contain
-- personal complaints and PII across every user, and every read already
-- goes through get_support_messages/the /api/support/messages proxy,
-- both of which verify the requesting phone owns the conversation before
-- returning anything.
--
-- security-194 added `using (true)` + `grant select ... to anon,
-- authenticated` to enable Realtime for a streaming AI-reply feature,
-- copying the pattern already used for rides/driver_locations/
-- dispatch_offers — without checking that support_messages had already
-- been deliberately excluded from that pattern for a real reason. That
-- policy/grant would have let anyone with the public anon key read every
-- user's support conversation directly via PostgREST, bypassing the
-- phone-ownership check entirely. Reverted here before it could be
-- exploited; the streaming feature itself is reworked to poll the
-- existing phone-verified path more frequently instead of using Realtime.

drop policy if exists support_messages_select_all on public.support_messages;

revoke select on public.support_messages from anon, authenticated;

do $$
begin
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'support_messages'
  ) then
    alter publication supabase_realtime drop table public.support_messages;
  end if;
end $$;

-- Leave `streaming` and RLS-enabled as-is — the column is still useful
-- (the client knows a reply is mid-stream vs. finished even over
-- polling), and RLS staying enabled with no policy is this project's
-- normal "RPC-only access" pattern, not a regression.
