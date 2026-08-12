import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database, Json } from '../lib/database.types.ts'

export type VerificationTier = 'ready' | 'research' | 'hold'
export type VerificationCandidate = {
  id: string
  business_name: string
  city: string
  state: string
  category: string
  subcategory: string
  website_url: string
  instagram_handle: string
  public_email: string
  public_phone: string
  external_source_url: string
  source_address: string
  source_category: string
  source_subcategory: string
  classification_confidence: number
  classification_method: string
  verification_score: number
  verification_tier: VerificationTier
  verification_reasons: string[]
  priority_score: number
  source_key: string
  review_status: string
  source_name: string
  ownership_signal: string
}
export type VerificationSnapshot = {
  counts: { ready: number; research: number; hold: number; pending_reviews: number; approved_reviews: number }
  candidates: VerificationCandidate[]
  generated_at: string
}

type TypedClient = SupabaseClient<Database>
type RpcResult = { data: Json | null; error: { message: string } | null }
const numberValue=(value:unknown)=>{const n=Number(value);return Number.isFinite(n)?n:0}
const recordValue=(value:unknown):Record<string,unknown>=>Boolean(value)&&typeof value==='object'&&!Array.isArray(value)?value as Record<string,unknown>:{}
const arrayValue=(value:unknown):Record<string,unknown>[]=>Array.isArray(value)?value.filter((item):item is Record<string,unknown>=>Boolean(item)&&typeof item==='object'&&!Array.isArray(item)):[]
const tierValue=(value:unknown):VerificationTier=>value==='ready'||value==='research'?value:'hold'

function rpcClient(supabase:TypedClient){return supabase.rpc.bind(supabase) as unknown as (fn:string,args:Record<string,unknown>)=>Promise<RpcResult>}
function parseSnapshot(value:Json):VerificationSnapshot{
  const root=recordValue(value),counts=recordValue(root.counts)
  return {
    counts:{ready:numberValue(counts.ready),research:numberValue(counts.research),hold:numberValue(counts.hold),pending_reviews:numberValue(counts.pending_reviews),approved_reviews:numberValue(counts.approved_reviews)},
    candidates:arrayValue(root.candidates).map(item=>({
      id:String(item.id||''),business_name:String(item.business_name||''),city:String(item.city||''),state:String(item.state||''),category:String(item.category||''),subcategory:String(item.subcategory||''),website_url:String(item.website_url||''),instagram_handle:String(item.instagram_handle||''),public_email:String(item.public_email||''),public_phone:String(item.public_phone||''),external_source_url:String(item.external_source_url||''),source_address:String(item.source_address||''),source_category:String(item.source_category||''),source_subcategory:String(item.source_subcategory||''),classification_confidence:numberValue(item.classification_confidence),classification_method:String(item.classification_method||''),verification_score:numberValue(item.verification_score),verification_tier:tierValue(item.verification_tier),verification_reasons:Array.isArray(item.verification_reasons)?item.verification_reasons.map(String):[],priority_score:numberValue(item.priority_score),source_key:String(item.source_key||''),review_status:String(item.review_status||''),source_name:String(item.source_name||''),ownership_signal:String(item.ownership_signal||'')
    })),
    generated_at:String(root.generated_at||'')
  }
}

export async function fetchVerificationSnapshot(supabase:TypedClient,city?:string|null,limit=250){
  const {data,error}=await rpcClient(supabase)('black_pages_staff_verification_snapshot',{p_city:city||null,p_limit:limit})
  if(error||data==null)return{snapshot:null,error:error?.message||'Verification queue is unavailable.'}
  return{snapshot:parseSnapshot(data),error:''}
}

export async function submitBatchVerification(supabase:TypedClient,input:{candidateIds:string[];decision:'approve'|'reject'|'needs_more_evidence';reason:string}){
  const items=input.candidateIds.map(candidate_id=>({candidate_id,decision:input.decision}))
  const {data,error}=await rpcClient(supabase)('black_pages_staff_batch_candidate_review',{p_items:items,p_reason:input.reason})
  if(error||data==null)return{result:null,error:error?.message||'Batch review could not be saved.'}
  return{result:recordValue(data),error:''}
}
