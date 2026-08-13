import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database, Json } from '../lib/database.types.ts'

type Client=SupabaseClient<Database>
type RpcResult={data:Json|null;error:{message:string}|null}
const rec=(v:unknown):Record<string,unknown>=>Boolean(v)&&typeof v==='object'&&!Array.isArray(v)?v as Record<string,unknown>:{}
const arr=(v:unknown):Record<string,unknown>[]=>Array.isArray(v)?v.filter((x):x is Record<string,unknown>=>Boolean(x)&&typeof x==='object'&&!Array.isArray(x)):[]
const num=(v:unknown)=>Number.isFinite(Number(v))?Number(v):0
const strings=(v:unknown)=>Array.isArray(v)?v.map(String):[]
const rpc=(s:Client)=>s.rpc.bind(s) as unknown as (fn:string,args:Record<string,unknown>)=>Promise<RpcResult>

export type PublicationDraft={id:string;identity_id:string;business_name:string;category:string;subcategory:string;city:string;state:string;address:string;postal_code:string;phone:string;business_email:string;website_url:string;instagram_handle:string;short_description:string;specialties:string[];source_names:string[];evidence_urls:string[];completeness_score:number;missing_fields:string[];status:string;listing_id:string;updated_at:string}
export type PublicationSnapshot={counts:{ready:number;draft:number;published:number;avg_completeness:number};drafts:PublicationDraft[];generated_at:string}

function parse(v:Json):PublicationSnapshot{const r=rec(v),c=rec(r.counts);return{counts:{ready:num(c.ready),draft:num(c.draft),published:num(c.published),avg_completeness:num(c.avg_completeness)},drafts:arr(r.drafts).map(x=>({id:String(x.id||''),identity_id:String(x.identity_id||''),business_name:String(x.business_name||''),category:String(x.category||''),subcategory:String(x.subcategory||''),city:String(x.city||''),state:String(x.state||''),address:String(x.address||''),postal_code:String(x.postal_code||''),phone:String(x.phone||''),business_email:String(x.business_email||''),website_url:String(x.website_url||''),instagram_handle:String(x.instagram_handle||''),short_description:String(x.short_description||''),specialties:strings(x.specialties),source_names:strings(x.source_names),evidence_urls:strings(x.evidence_urls),completeness_score:num(x.completeness_score),missing_fields:strings(x.missing_fields),status:String(x.status||''),listing_id:String(x.listing_id||''),updated_at:String(x.updated_at||'')})),generated_at:String(r.generated_at||'')}}

export async function fetchPublicationSnapshot(s:Client,limit=250){const{data,error}=await rpc(s)('black_pages_staff_publication_snapshot',{p_limit:limit});if(error||data==null)return{snapshot:null,error:error?.message||'Publication factory unavailable.'};return{snapshot:parse(data),error:''}}
export async function publishDraft(s:Client,draftId:string,reason:string){const{data,error}=await rpc(s)('black_pages_staff_publish_draft',{p_draft_id:draftId,p_reason:reason});if(error||data==null)return{result:null,error:error?.message||'Draft could not be published.'};return{result:rec(data),error:''}}
