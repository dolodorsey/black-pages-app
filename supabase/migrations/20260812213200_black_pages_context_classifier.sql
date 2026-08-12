-- Second classification lane: use notes, source labels, business name and URLs as context.
-- Conservative thresholds leave ambiguous records unresolved.
create or replace function public.black_pages_context_classify_batch(p_limit integer default 10000)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','extensions','auth' as $$
declare
  v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');
  v_limit integer:=least(30000,greatest(1,coalesce(p_limit,10000)));
  v_alias integer:=0;v_semantic integer:=0;
begin
  if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then
    raise exception 'Staff access required' using errcode='42501';
  end if;
  with targets as(
    select q.id,lower(concat_ws(' ',q.business_name,q.source_category,q.source_subcategory,q.category,q.notes,
      regexp_replace(coalesce(q.website_url,''),'https?://|www\.|[-_/?.=&]+',' ','g'),
      regexp_replace(coalesce(q.external_source_url,''),'https?://|www\.|[-_/?.=&]+',' ','g'))) context_text
    from public.black_pages_candidate_queue q
    where (q.subcategory is null or btrim(q.subcategory)='') and q.pipeline_stage not in('published','rejected','do_not_contact')
    order by q.priority_score desc,q.id limit v_limit
  ),matches as(
    select distinct on(t.id) t.id,a.category_slug,a.subcategory_slug,least(.97,greatest(.78,a.confidence*.94)) confidence
    from targets t join public.black_pages_taxonomy_aliases a on a.active and length(a.alias)>=3 and t.context_text like '%'||lower(a.alias)||'%'
    order by t.id,a.confidence desc,length(a.alias) desc
  ),upd as(
    update public.black_pages_candidate_queue q set category=m.category_slug,subcategory=m.subcategory_slug,
      classification_confidence=m.confidence,classification_method='context_alias',classified_at=now(),updated_at=now()
    from matches m where q.id=m.id returning q.id
  )select count(*)::int into v_alias from upd;

  with targets as(
    select q.id,q.category,lower(concat_ws(' ',q.business_name,q.source_category,q.source_subcategory,q.notes,
      regexp_replace(coalesce(q.website_url,''),'https?://|www\.|[-_/?.=&]+',' ','g'))) context_text
    from public.black_pages_candidate_queue q
    where (q.subcategory is null or btrim(q.subcategory)='') and q.category is not null and q.pipeline_stage not in('published','rejected','do_not_contact')
    order by q.priority_score desc,q.id limit v_limit
  ),scored as(
    select distinct on(t.id) t.id,s.category_slug,s.slug subcategory_slug,
      greatest(word_similarity(lower(s.name),t.context_text),word_similarity(replace(lower(s.slug),'-',' '),t.context_text)) score
    from targets t join public.black_pages_subcategories s on s.active and s.category_slug=t.category
    where greatest(word_similarity(lower(s.name),t.context_text),word_similarity(replace(lower(s.slug),'-',' '),t.context_text))>=.72
    order by t.id,score desc,s.slug
  ),upd as(
    update public.black_pages_candidate_queue q set subcategory=s.subcategory_slug,
      classification_confidence=least(.91,greatest(.78,s.score)),classification_method='context_semantic',classified_at=now(),updated_at=now()
    from scored s where q.id=s.id returning q.id
  )select count(*)::int into v_semantic from upd;
  return jsonb_build_object('context_alias_classified',v_alias,'context_semantic_classified',v_semantic,
    'classified_total',v_alias+v_semantic,'remaining_unclassified',(select count(*) from public.black_pages_candidate_queue where subcategory is null or btrim(subcategory)=''));
end $$;
revoke all on function public.black_pages_context_classify_batch(integer) from public,anon,authenticated;
grant execute on function public.black_pages_context_classify_batch(integer) to authenticated,service_role;

select public.black_pages_context_classify_batch(30000);
