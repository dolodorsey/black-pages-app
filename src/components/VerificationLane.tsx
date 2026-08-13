import { useEffect, useMemo, useState } from 'react'
import { AlertTriangle, CheckCircle2, ExternalLink, Layers3, RefreshCw, Search, ShieldCheck } from 'lucide-react'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../lib/database.types.ts'
import { fetchIdentityReviewSnapshot, submitIdentityBatchReview, type IdentityReviewSnapshot, type IdentityReviewTier } from '../services/identityVerification.ts'
import './VerificationLane.css'

type BatchSize=25|50|100
export function VerificationLane({supabase,city}:{supabase:SupabaseClient<Database>;city:string}){
  const[snapshot,setSnapshot]=useState<IdentityReviewSnapshot|null>(null)
  const[tier,setTier]=useState<IdentityReviewTier>('ready')
  const[query,setQuery]=useState('')
  const[batchSize,setBatchSize]=useState<BatchSize>(25)
  const[selected,setSelected]=useState<string[]>([])
  const[reason,setReason]=useState('')
  const[loading,setLoading]=useState(true)
  const[busy,setBusy]=useState(false)
  const[error,setError]=useState('')
  const[success,setSuccess]=useState('')

  async function load(){setLoading(true);setError('');const result=await fetchIdentityReviewSnapshot(supabase,city,1000);if(result.error||!result.snapshot)setError(result.error||'Business identity review queue is unavailable.');else setSnapshot(result.snapshot);setLoading(false)}
  useEffect(()=>{setSelected([]);void load()},[city]) // eslint-disable-line react-hooks/exhaustive-deps

  const filtered=useMemo(()=>{const term=query.trim().toLowerCase();return(snapshot?.identities||[]).filter(item=>item.review_tier===tier&&(!term||`${item.business_name} ${item.city} ${item.category} ${item.subcategory} ${item.source_names.join(' ')} ${item.corroboration_reasons.join(' ')}`.toLowerCase().includes(term)))},[snapshot,tier,query])
  const visible=filtered.slice(0,batchSize)
  const allVisibleSelected=visible.length>0&&visible.every(item=>selected.includes(item.identity_id))
  function toggle(id:string){setSelected(current=>current.includes(id)?current.filter(item=>item!==id):current.length>=batchSize?current:[...current,id])}
  function toggleAll(){const ids=visible.map(item=>item.identity_id);setSelected(current=>allVisibleSelected?current.filter(id=>!ids.includes(id)):[...new Set([...current,...ids])].slice(0,batchSize))}
  async function review(decision:'approve'|'reject'|'needs_more_evidence'){if(!selected.length||!reason.trim()||busy)return;setBusy(true);setError('');setSuccess('');const response=await submitIdentityBatchReview(supabase,{identityIds:selected,decision,reason:reason.trim()});if(response.error)setError(response.error);else{const identities=Number(response.result?.identities_reviewed||selected.length),records=Number(response.result?.candidate_records_advanced||0);setSuccess(`${identities} businesses reviewed across ${records} candidate records. No public listings were created automatically.`);setSelected([]);setReason('');await load()}setBusy(false)}

  return <section className="verification-lane">
    <div className="verification-head"><div><span><ShieldCheck size={14}/> MASTER BUSINESS REVIEW</span><h2>Review businesses once, with every source attached.</h2><p>Corroboration now separates explicit Black-owned evidence from membership-only discovery. Chamber membership by itself routes to Research; certification, Black Restaurant Week, or multiple explicit ownership sources can reach Ready.</p></div><button onClick={()=>void load()} disabled={loading}><RefreshCw size={15} className={loading?'spin':''}/></button></div>

    <div className="verification-identity-stats"><span><b>{snapshot?.counts.multi_source||0}</b> multi-source businesses</span><span><b>{snapshot?.counts.duplicate_rows_collapsed||0}</b> duplicate discovery rows grouped</span></div>
    <div className="verification-kpis">
      <button className={tier==='ready'?'active':''} onClick={()=>{setTier('ready');setSelected([])}}><span>Ready</span><strong>{snapshot?.counts.ready||0}</strong><small>Explicit/corroborated ownership evidence</small></button>
      <button className={tier==='research'?'active':''} onClick={()=>{setTier('research');setSelected([])}}><span>Research</span><strong>{snapshot?.counts.research||0}</strong><small>Membership or single weak source</small></button>
      <button className={tier==='hold'?'active':''} onClick={()=>{setTier('hold');setSelected([])}}><span>Hold</span><strong>{snapshot?.counts.hold||0}</strong><small>No meaningful ownership proof</small></button>
    </div>

    <div className="verification-batch-bar"><label><span>Review batch</span><select value={batchSize} onChange={event=>{setBatchSize(Number(event.target.value) as BatchSize);setSelected([])}}><option value={25}>25 businesses</option><option value={50}>50 businesses</option><option value={100}>100 businesses</option></select></label><div><strong>{filtered.length.toLocaleString()}</strong><small>{tier} businesses in this market</small></div></div>
    <div className="verification-tools"><label><Search size={14}/><input value={query} onChange={event=>setQuery(event.target.value)} placeholder="Search business, type, city or evidence reason"/></label><button onClick={toggleAll} disabled={!visible.length}>{allVisibleSelected?'Clear batch':`Select ${Math.min(batchSize,visible.length)}`}</button></div>

    {error&&<div className="verification-message error"><AlertTriangle size={15}/>{error}</div>}
    {success&&<div className="verification-message success"><CheckCircle2 size={15}/>{success}</div>}

    <div className="verification-list identity-list">
      {loading&&!snapshot?<div className="verification-empty">Resolving business identities and corroboration evidence…</div>:visible.map(item=><article key={item.identity_id} className={selected.includes(item.identity_id)?'selected':''}>
        <label className="verification-check"><input type="checkbox" checked={selected.includes(item.identity_id)} onChange={()=>toggle(item.identity_id)}/><i/></label>
        <div className="verification-candidate">
          <div className="verification-candidate-title"><div><strong>{item.business_name}</strong><span>{item.city}{item.state?`, ${item.state}`:''}</span></div><b title="Corroboration score">{Math.round(item.corroboration_score||item.max_verification_score)}</b></div>
          <div className="verification-meta"><span>{item.category||'Unclassified'}</span>{item.subcategory&&<span>{item.subcategory}</span>}{item.certified_black_source&&<span className="certified-source">Certified source</span>}</div>
          <div className="identity-bundle-summary"><span><Layers3 size={11}/>{item.source_count} source{item.source_count===1?'':'s'}</span><span>{item.member_count} discovery record{item.member_count===1?'':'s'} grouped</span><span>{Math.round(item.identity_confidence*100)}% identity match</span></div>
          <div className="verification-reasons">{item.corroboration_reasons.map(value=><i key={value}>{value.replaceAll('_',' ')}</i>)}</div>
          <div className="identity-source-badges">{item.source_names.slice(0,5).map(value=><i key={value}>{value}</i>)}{item.source_names.length>5&&<i>+{item.source_names.length-5} more</i>}</div>
          <div className="verification-contact">{item.source_address&&<span>{item.source_address}</span>}{item.public_phone&&<span>{item.public_phone}</span>}{item.website_url&&<span>Website present</span>}</div>
          <div className="identity-evidence-links">{item.evidence.filter(e=>e.source_url).slice(0,3).map((e,index)=><a key={`${e.candidate_id}-${index}`} href={e.source_url} target="_blank" rel="noreferrer">{e.source_name||e.source_key||'Source evidence'} <ExternalLink size={11}/></a>)}</div>
        </div>
      </article>)}
      {!loading&&visible.length===0&&<div className="verification-empty">No {tier} businesses match this view.</div>}
    </div>

    <div className="verification-decision">
      <div><strong>{selected.length} business identities selected</strong><small>Batch limit {batchSize}. One decision applies to the grouped evidence bundle and is fully audited.</small></div>
      <textarea value={reason} onChange={event=>setReason(event.target.value)} placeholder="Required human review reason / evidence note" rows={3}/>
      <div className="verification-actions">
        {tier==='ready'&&<button className="approve" onClick={()=>void review('approve')} disabled={!selected.length||!reason.trim()||busy}><CheckCircle2 size={15}/>Approve evidence</button>}
        <button onClick={()=>void review('needs_more_evidence')} disabled={!selected.length||!reason.trim()||busy}>More evidence</button>
        <button className="reject" onClick={()=>void review('reject')} disabled={!selected.length||!reason.trim()||busy}>Reject</button>
      </div>
      <p><ShieldCheck size={13}/>Approval changes private verification status only. Public listing creation remains a separate publication step.</p>
    </div>
  </section>
}
