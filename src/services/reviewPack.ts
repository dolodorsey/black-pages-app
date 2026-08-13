import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database, Json } from '../lib/database.types.ts'

export type ReviewRecommendation='approve'|'reject'|'needs_more_evidence'
export type ReviewPackItem={identity_id:string;rank:number;recommended_decision:ReviewRecommendation;recommendation_reason:string;source_snapshot:{business_name:string;city:string;state:string;source_keys:string[];source_names:string[];evidence_urls:string[];legacy_score:number}}
export type ReviewPackSnapshot={pack:{pack_key:string;title:string;status:string;total_items:number}|null;counts:{approve:number;needs_more_evidence:number;reject:number};items:ReviewPackItem[]}
type TypedClient=SupabaseClient<Database>;type RpcResult={data:Json|null;error:{message:string}|null}
const obj=(v:unknown):Record<string,unknown>=>v&&typeof v==='object'&&!Array.isArray(v)?v as Record<string,unknown>:{}
const arr=(v:unknown):Record<string,unknown>[]=>Array.isArray(v)?v.filter((x):x is Record<string,unknown>=>Boolean(x)&&typeof x==='object'&&!Array.isArray(x)):[]
const strings=(v:unknown)=>Array.isArray(v)?v.map(String).filter(Boolean):[]
const num=(v:unknown)=>{const n=Number(v);return Number.isFinite(n)?n:0}
function rpc(s:TypedClient){return s.rpc.bind(s) as unknown as(fn:string,args:Record<string,unknown>)=>Promise<RpcResult>}
export async function fetchFirst100ReviewPack(supabase:TypedClient){const{data,error}=await rpc(supabase)('black_pages_staff_review_pack_snapshot',{p_pack_key:'first_100_ready_20260813'});if(error||data==null)return{snapshot:null,error:error?.message||'Review pack unavailable.'};const root=obj(data),p=obj(root.pack),c=obj(root.counts);return{snapshot:{pack:Object.keys(p).length?{pack_key:String(p.pack_key||''),title:String(p.title||''),status:String(p.status||''),total_items:num(p.total_items)}:null,counts:{approve:num(c.approve),needs_more_evidence:num(c.needs_more_evidence),reject:num(c.reject)},items:arr(root.items).map(i=>{const s=obj(i.source_snapshot);const d=String(i.recommended_decision||'needs_more_evidence') as ReviewRecommendation;return{identity_id:String(i.identity_id||''),rank:num(i.rank),recommended_decision:d,recommendation_reason:String(i.recommendation_reason||''),source_snapshot:{business_name:String(s.business_name||''),city:String(s.city||''),state:String(s.state||''),source_keys:strings(s.source_keys),source_names:strings(s.source_names),evidence_urls:strings(s.evidence_urls),legacy_score:num(s.legacy_score)}}})},error:''}}
