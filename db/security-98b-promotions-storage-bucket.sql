-- Public bucket for promo banner images (admin-uploaded, recommended
-- 1080×566), same public-read + anon-insert pattern as the existing
-- 'marketplace' bucket (admin.astro has no Supabase Auth session to gate
-- storage writes with — RPC password checks are this app's auth model,
-- not RLS — same trust level already accepted for that bucket).
insert into storage.buckets (id, name, public)
values ('promotions', 'promotions', true)
on conflict (id) do nothing;

drop policy if exists "promotions public read" on storage.objects;
create policy "promotions public read" on storage.objects
  for select using (bucket_id = 'promotions');

drop policy if exists "promotions anon upload" on storage.objects;
create policy "promotions anon upload" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'promotions');
