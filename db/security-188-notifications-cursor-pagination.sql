-- security-188: cursor-based pagination for notifications
-- آمن لإعادة التشغيل (idempotent) — safe to re-run.
--
-- notifications has 12,021+ rows and list_notifications only ever
-- returned the newest 50 with no way to page further — anything older
-- was structurally unreachable. This adds an optional keyset cursor
-- (created_at, id) so the same RPC can be called again for the next
-- page; existing callers that pass no cursor get identical behavior
-- to before.

create index if not exists idx_notifications_phone_created_id
  on public.notifications (phone, created_at desc, id desc);

create or replace function public.list_notifications(
  p_phone text,
  p_limit integer default 50,
  p_after_created_at timestamptz default null,
  p_after_id uuid default null
)
returns setof notifications
language sql
security definer
set search_path to 'public', 'extensions'
as $function$
  select *
  from public.notifications
  where phone = p_phone
    and (
      p_after_created_at is null
      or created_at < p_after_created_at
      or (created_at = p_after_created_at and id < p_after_id)
    )
  order by created_at desc, id desc
  limit greatest(1, least(p_limit, 200));
$function$;
