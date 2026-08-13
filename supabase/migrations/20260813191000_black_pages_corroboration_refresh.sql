-- Keep ownership corroboration ranking current as new source evidence lands.
select public.black_pages_refresh_corroboration_scores();
do $b$ declare r record;begin for r in select jobid from cron.job where jobname='black-pages-corroboration-refresh' loop perform cron.unschedule(r.jobid);end loop;end $b$;
select cron.schedule('black-pages-corroboration-refresh','6,16,26,36,46,56 * * * *',$$select public.black_pages_refresh_corroboration_scores();$$);