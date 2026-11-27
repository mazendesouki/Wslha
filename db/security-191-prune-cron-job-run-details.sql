-- security-191: stop cron.job_run_details from silently filling the database
-- آمن لإعادة التشغيل (idempotent) — safe to re-run.
--
-- Found while setting up usage monitoring: cron.job_run_details (pg_cron's
-- own execution-log table — one row per job run, never auto-cleaned) had
-- grown to 267 MB over ~4 months, out of a 275 MB total database size on
-- the free tier's 500 MB cap. That's log bloat from jobs running every
-- 10-60 seconds, not real app data — pruned here (keeping 3 days of
-- history) and brought the database down to 45 MB. This job keeps it
-- from happening again.

create or replace function public._prune_cron_job_run_details()
returns void
language sql
security definer
set search_path to 'public', 'cron'
as $$
  delete from cron.job_run_details where start_time < now() - interval '3 days';
$$;

select cron.schedule('prune-cron-job-run-details', '17 3 * * *', $$select public._prune_cron_job_run_details();$$);
