-- National source wave. Chamber membership is discovery evidence only; corroboration is required before ownership approval.
insert into public.black_pages_external_sources(source_key,source_name,adapter,base_url,ownership_signal,active,priority,notes)
values
 ('palm_beach_black_chamber','Black Chamber of Commerce of Palm Beach County','growthzone_v2','https://business.blackchamberpbc.com/activememberdirectory/FindStartsWith?term=%23%21','black_chamber_directory',false,111,'GrowthZone source. Membership alone does not prove Black ownership; activate after A-shard QA.'),
 ('greater_austin_black_chamber','Greater Austin Black Chamber of Commerce','chambermaster_v1','https://www.austinbcc.org/list','black_chamber_directory',false,111,'ChamberMaster source. Directory includes institutions and corporate members; ownership corroboration required.'),
 ('aacc_pa_nj_de','African American Chamber of Commerce of PA, NJ & DE','chambermaster_v1','https://membership.aachamber.com/list','black_chamber_directory',false,111,'ChamberMaster source. Membership includes corporations/institutions; ownership corroboration required.'),
 ('black_chamber_arizona','Black Chamber of Arizona — Business Directory','bcaz_directory_v1','https://blackchamberaz.org/bcaz-directory/','black_business_directory',false,109,'Staged for dedicated parser QA. Site describes directory as Black-owned businesses; do not activate until parser/data QA passes.')
on conflict(source_key) do update set source_name=excluded.source_name,adapter=excluded.adapter,base_url=excluded.base_url,ownership_signal=excluded.ownership_signal,priority=excluded.priority,notes=excluded.notes,updated_at=now();

create or replace function public.black_pages_queue_chambermaster_sources(p_source_keys text[] default null)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare s record;letter text;v_url text;v_jobs integer:=0;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501';end if;
 for s in select * from public.black_pages_external_sources where adapter='chambermaster_v1' and (p_source_keys is null or source_key=any(p_source_keys)) order by priority desc loop
  foreach letter in array array['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'] loop
   v_url:=rtrim(s.base_url,'/')||'/searchalpha/'||lower(letter);
   insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,status,attempt_count,error_message,started_at,completed_at,result_count,updated_at)
   values(s.source_key,null,null,null,ascii(letter)-64,v_url,100,'pending',0,null,null,null,0,now())
   on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,started_at=null,completed_at=null,result_count=0,updated_at=now();
   v_jobs:=v_jobs+1;
  end loop;
 end loop;
 return jsonb_build_object('jobs_queued',v_jobs,'adapter','chambermaster_v1');
end $$;
revoke all on function public.black_pages_queue_chambermaster_sources(text[]) from public,anon,authenticated;
grant execute on function public.black_pages_queue_chambermaster_sources(text[]) to service_role;
