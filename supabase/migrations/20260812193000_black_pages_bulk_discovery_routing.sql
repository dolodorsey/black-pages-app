-- THE BLACK PAGES: route bulk-discovered candidates into the correct research lane.
-- Website research stays high-throughput; Instagram-only and endpoint-less leads do not waste website-worker capacity.

create or replace function public.black_pages_route_research_candidate()
returns trigger
language plpgsql
set search_path='pg_catalog','public'
as $function$
begin
  if new.pipeline_stage='research'
     and new.ownership_evidence_status in ('unreviewed','insufficient')
     and (
       new.assigned_researcher is null
       or new.assigned_researcher in (
         'black-pages-research-worker',
         'black-pages-owner-verification-agent',
         'black-pages-social-research-worker',
         'black-pages-endpoint-enrichment'
       )
     ) then
    if new.website_url ~* '^https?://(www\.)?instagram\.com/' then
      new.assigned_researcher := 'black-pages-social-research-worker';
      new.data_quality_status := 'social_lookup_required';
    elsif nullif(btrim(coalesce(new.website_url,'')),'') is null then
      new.assigned_researcher := 'black-pages-endpoint-enrichment';
      new.data_quality_status := 'endpoint_lookup_required';
    else
      new.assigned_researcher := 'black-pages-research-worker';
      if new.data_quality_status in ('social_lookup_required','endpoint_lookup_required','needs_enrichment') then
        new.data_quality_status := 'research_ready';
      end if;
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists black_pages_route_research_candidate on public.black_pages_candidate_queue;
create trigger black_pages_route_research_candidate
before insert or update of website_url,pipeline_stage,ownership_evidence_status,assigned_researcher
on public.black_pages_candidate_queue
for each row execute function public.black_pages_route_research_candidate();

-- Re-route the current private queue immediately.
update public.black_pages_candidate_queue
set assigned_researcher='black-pages-social-research-worker',
    data_quality_status='social_lookup_required',
    next_action_at=now(),
    updated_at=now()
where pipeline_stage='research'
  and ownership_evidence_status in ('unreviewed','insufficient')
  and website_url ~* '^https?://(www\.)?instagram\.com/'
  and coalesce(assigned_researcher,'') in ('','black-pages-research-worker','black-pages-owner-verification-agent','black-pages-social-research-worker');

update public.black_pages_candidate_queue
set assigned_researcher='black-pages-endpoint-enrichment',
    data_quality_status='endpoint_lookup_required',
    next_action_at=now(),
    updated_at=now()
where pipeline_stage='research'
  and ownership_evidence_status in ('unreviewed','insufficient')
  and nullif(btrim(coalesce(website_url,'')),'') is null
  and coalesce(assigned_researcher,'') in ('','black-pages-research-worker','black-pages-owner-verification-agent','black-pages-endpoint-enrichment');

update public.black_pages_candidate_queue
set assigned_researcher='black-pages-research-worker',
    data_quality_status=case
      when data_quality_status in ('social_lookup_required','endpoint_lookup_required','needs_enrichment') then 'research_ready'
      else data_quality_status
    end,
    next_action_at=least(next_action_at,now()),
    updated_at=now()
where pipeline_stage='research'
  and ownership_evidence_status in ('unreviewed','insufficient')
  and nullif(btrim(coalesce(website_url,'')),'') is not null
  and website_url !~* '^https?://(www\.)?instagram\.com/'
  and coalesce(assigned_researcher,'') in ('','black-pages-research-worker','black-pages-owner-verification-agent');

create or replace view public.black_pages_bulk_research_lane_health
with (security_invoker=true)
as
select
  case
    when assigned_researcher='black-pages-social-research-worker' then 'social_lookup'
    when assigned_researcher='black-pages-endpoint-enrichment' then 'endpoint_enrichment'
    when assigned_researcher='black-pages-research-worker' then 'website_research'
    else 'other'
  end as lane,
  count(*)::integer as candidates,
  count(*) filter (where next_action_at<=now())::integer as due_now,
  count(*) filter (where source_external_key like 'contacts_master:%')::integer as enterprise_seed_candidates,
  round(avg(priority_score),1) as average_priority
from public.black_pages_candidate_queue
where pipeline_stage='research'
  and ownership_evidence_status in ('unreviewed','insufficient')
group by 1;

revoke all on public.black_pages_bulk_research_lane_health from public,anon,authenticated;
grant select on public.black_pages_bulk_research_lane_health to service_role;
