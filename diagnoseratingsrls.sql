-- Diagnostic only — no changes. Run in Supabase SQL Editor and share
-- the results so we can see exactly why inserts into `ratings` are
-- silently failing (the table is currently empty despite completed
-- trips and an explicit rating submission).

-- 1) Is RLS even enabled on ratings, and does a permissive policy exist?
select relrowsecurity, relforcerowsecurity
from pg_class
where relname = 'ratings';

select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'ratings';

-- 2) Does the anon role actually have INSERT granted on the table?
select grantee, privilege_type
from information_schema.role_table_grants
where table_name = 'ratings';

-- 3) Column constraints — confirms rated_by/NOT NULL/CHECK are as expected.
select column_name, is_nullable, column_default
from information_schema.columns
where table_name = 'ratings'
order by ordinal_position;
