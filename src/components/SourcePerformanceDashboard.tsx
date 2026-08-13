import { useEffect, useMemo, useState } from 'react'
import { Activity, AlertTriangle, Database, RefreshCw, ShieldCheck, TrendingUp } from 'lucide-react'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../lib/database.types.ts'
import { fetchSourcePerformance,type SourcePerformanceSnapshot } from '../services/sourcePerformance.ts'
import './SourcePerformanceDashboard.css'

export function SourcePerformanceDashboard({supabase}:{supabase:SupabaseClient<Database>}){
 const[snapshot,setSnapshot]=useState<SourcePerformanceSnapshot|null>(null);const[loading,setLoading]=useState(true);const[error,setError]=useState('');const[query,setQuery]=useState('')
 async function load(){setLoading(true);setError('');const r=await fetchSourcePerformance(supabase);if(r.error||!r.snapshot)setError(r.error||'Source dashboard unavailable.');else setSnapshot(r.snapshot);setLoading(false)}
 useEffect(()=>{void load()},[]) // eslint-disable-line react-hooks/exhaustive-deps
 const rows=useMemo(()=>{const q=query.trim().toLowerCase();return(snapshot?.sources||[]).filter(x=>!q||`${x.source_name} ${x.ownership_signal} ${x.adapter}`.toLowerCase().includes(q))},[snapshot,query])
 return <section className="source-performance">
  <div className="source-head"><div><span><Activity size={14}/> SOURCE COVERAGE</span><h2>Know exactly which sources are producing useful inventory.</h2><p>Discovery volume is separated from unique businesses, duplicate merges, verification conversion, crawl reliability and final publication.</p></div><button onClick={()=>void load()} disabled={loading}><RefreshCw size={15} className={loading?'spin':''}/></button></div>
  <div className="source-kpis"><article><ShieldCheck/><small>Active sources</small><strong>{snapshot?.totals.active_sources||0}</strong></article><article><Database/><small>External candidates</small><strong>{(snapshot?.totals.candidate_records||0).toLocaleString()}</strong></article><article><TrendingUp/><small>Business identities</small><strong>{(snapshot?.totals.business_identities||0).toLocaleString()}</strong></article><article><Activity/><small>Publication ready</small><strong>{snapshot?.totals.publication_ready||0}</strong></article></div>
  <label className="source-search">Search source, type, or adapter<input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Black Restaurant Week, chamber, curated guide…"/></label>
  {error&&<div className="source-error"><AlertTriangle size={15}/>{error}</div>}
  <div className="source-table"><div className="source-row source-header"><span>Source</span><span>Unique / raw</span><span>Dupes</span><span>Cities</span><span>Verify</span><span>Jobs</span><span>Bad rate</span></div>{loading&&!snapshot?<div className="source-empty">Calculating source ROI…</div>:rows.map(s=><article className="source-row" key={s.source_key}><div><strong>{s.source_name}</strong><small>{s.ownership_signal.replaceAll('_',' ')} · {s.active?'ACTIVE':'STAGED'}</small></div><span><b>{s.unique_businesses}</b> / {s.candidate_records}</span><span>{s.duplicate_records_merged}</span><span>{s.cities_covered}</span><span>{s.verification_conversion_pct}%</span><span>{s.successful_jobs}/{s.jobs}</span><span className={s.bad_job_rate_pct>20?'bad':''}>{s.bad_job_rate_pct}%</span></article>)}{!loading&&rows.length===0&&<div className="source-empty">No sources match this filter.</div>}</div>
 </section>
}
