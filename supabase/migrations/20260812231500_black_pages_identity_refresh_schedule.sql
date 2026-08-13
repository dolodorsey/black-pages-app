do $block$ declare r record;begin
 for r in select jobid from cron.job where jobname='black-pages-identity-refresh' loop perform cron.unschedule(r.jobid);end loop;
end $block$;
select cron.schedule('black-pages-identity-refresh','3,13,23,33,43,53 * * * *',$$select public.black_pages_refresh_identity_resolution();$$);
