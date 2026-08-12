import { useEffect, useMemo, useState } from 'react'
import { AlertTriangle, CheckCircle2, ExternalLink, RefreshCw, Search, ShieldCheck } from 'lucide-react'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../lib/database.types.ts'
import { fetchVerificationSnapshot, submitBatchVerification, type VerificationSnapshot, type VerificationTier } from '../services/verification.ts'
import './VerificationLane.css'

export function VerificationLane({ supabase, city }: { supabase: SupabaseClient<Database>; city: string }) {
  const [snapshot, setSnapshot] = useState<VerificationSnapshot | null>(null)
  const [tier, setTier] = useState<VerificationTier>('ready')
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState<string[]>([])
  const [reason, setReason] = useState('')
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  async function load() {
    setLoading(true); setError('')
    const result=await fetchVerificationSnapshot(supabase,city,500)
    if(result.error||!result.snapshot)setError(result.error||'Verification queue is unavailable.')
    else setSnapshot(result.snapshot)
    setLoading(false)
  }

  useEffect(()=>{setSelected([]);void load()},[city]) // eslint-disable-line react-hooks/exhaustive-deps

  const visible=useMemo(()=>{
    const term=query.trim().toLowerCase()
    return (snapshot?.candidates||[]).filter(item=>item.verification_tier===tier&&item.review_status!=='approved'&&(!term||`${item.business_name} ${item.city} ${item.category} ${item.subcategory} ${item.source_name}`.toLowerCase().includes(term))).slice(0,50)
  },[snapshot,tier,query])
  const allVisibleSelected=visible.length>0&&visible.every(item=>selected.includes(item.id))

  function toggle(id:string){setSelected(current=>current.includes(id)?current.filter(item=>item!==id):[...current,id])}
  function toggleAll(){const ids=visible.map(item=>item.id);setSelected(current=>allVisibleSelected?current.filter(id=>!ids.includes(id)):[...new Set([...current,...ids])])}

  async function review(decision:'approve'|'reject'|'needs_more_evidence') {
    if(!selected.length||!reason.trim()||busy)return
    setBusy(true);setError('');setSuccess('')
    const response=await submitBatchVerification(supabase,{candidateIds:selected,decision,reason:reason.trim()})
    if(response.error)setError(response.error)
    else {setSuccess(`${Number(response.result?.reviewed||selected.length)} candidates reviewed. No listing was auto-published.`);setSelected([]);setReason('');await load()}
    setBusy(false)
  }

  return <section className="verification-lane">
    <div className="verification-head"><div><span><ShieldCheck size={14}/> MASS VERIFICATION</span><h2>Work the private candidate queue.</h2><p>Prechecks rank source strength, location, taxonomy confidence and duplicate risk. Every decision below is human-reviewed; approval never auto-publishes a listing.</p></div><button onClick={()=>void load()} disabled={loading}><RefreshCw size={15} className={loading?'spin':''}/></button></div>

    <div className="verification-kpis">
      <button className={tier==='ready'?'active':''} onClick={()=>{setTier('ready');setSelected([])}}><span>Ready</span><strong>{snapshot?.counts.ready||0}</strong><small>Strong source + evidence</small></button>
      <button className={tier==='research'?'active':''} onClick={()=>{setTier('research');setSelected([])}}><span>Research</span><strong>{snapshot?.counts.research||0}</strong><small>Needs targeted evidence</small></button>
      <button className={tier==='hold'?'active':''} onClick={()=>{setTier('hold');setSelected([])}}><span>Hold</span><strong>{snapshot?.counts.hold||0}</strong><small>Low evidence / duplicate risk</small></button>
    </div>

    <div className="verification-tools"><label><Search size={14}/><input value={query} onChange={event=>setQuery(event.target.value)} placeholder="Search candidate, type, source"/></label><button onClick={toggleAll} disabled={!visible.length}>{allVisibleSelected?'Clear visible':'Select visible'}</button></div>

    {error&&<div className="verification-message error"><AlertTriangle size={15}/>{error}</div>}
    {success&&<div className="verification-message success"><CheckCircle2 size={15}/>{success}</div>}

    <div className="verification-list">
      {loading&&!snapshot?<div className="verification-empty">Scoring the verification queue…</div>:visible.map(item=><article key={item.id} className={selected.includes(item.id)?'selected':''}>
        <label className="verification-check"><input type="checkbox" checked={selected.includes(item.id)} onChange={()=>toggle(item.id)}/><i/></label>
        <div className="verification-candidate">
          <div className="verification-candidate-title"><div><strong>{item.business_name}</strong><span>{item.city}{item.state?`, ${item.state}`:''}</span></div><b>{item.verification_score}</b></div>
          <div className="verification-meta"><span>{item.category||'Unclassified'}</span>{item.subcategory&&<span>{item.subcategory}</span>}{item.source_name&&<span>{item.source_name}</span>}</div>
          <div className="verification-reasons">{item.verification_reasons.map(value=><i key={value}>{value.replaceAll('_',' ')}</i>)}</div>
          <div className="verification-contact">{item.source_address&&<span>{item.source_address}</span>}{item.website_url&&<span>Website present</span>}{item.instagram_handle&&<span>@{item.instagram_handle}</span>}</div>
          {item.external_source_url&&<a href={item.external_source_url} target="_blank" rel="noreferrer">Review source evidence <ExternalLink size={12}/></a>}
        </div>
      </article>)}
      {!loading&&visible.length===0&&<div className="verification-empty">No {tier} candidates match this view.</div>}
    </div>

    <div className="verification-decision">
      <div><strong>{selected.length} selected</strong><small>Maximum 50 visible at once · every decision writes a reviewer audit record.</small></div>
      <textarea value={reason} onChange={event=>setReason(event.target.value)} placeholder="Required review reason / evidence note" rows={3}/>
      <div className="verification-actions">
        {tier==='ready'&&<button className="approve" onClick={()=>void review('approve')} disabled={!selected.length||!reason.trim()||busy}><CheckCircle2 size={15}/>Approve evidence</button>}
        <button onClick={()=>void review('needs_more_evidence')} disabled={!selected.length||!reason.trim()||busy}>More evidence</button>
        <button className="reject" onClick={()=>void review('reject')} disabled={!selected.length||!reason.trim()||busy}>Reject</button>
      </div>
      <p><ShieldCheck size={13}/> Batch approval changes the private candidate pipeline only. It does not create or publish a public directory listing.</p>
    </div>
  </section>
}
