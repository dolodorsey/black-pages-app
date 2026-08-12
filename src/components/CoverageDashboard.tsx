import { useEffect, useMemo, useState } from 'react'
import { AlertTriangle, CheckCircle2, ChevronRight, Database, MapPinned, RefreshCw, Search, Target } from 'lucide-react'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../lib/database.types.ts'
import { fetchCoverageSnapshot, type CoverageCell, type CoverageSnapshot } from '../services/coverage.ts'
import './CoverageDashboard.css'

type StatusFilter = 'all' | 'empty' | 'candidate_found' | 'covered'

export function CoverageDashboard({ supabase }: { supabase: SupabaseClient<Database> }) {
  const [snapshot, setSnapshot] = useState<CoverageSnapshot | null>(null)
  const [city, setCity] = useState('Atlanta')
  const [query, setQuery] = useState('')
  const [status, setStatus] = useState<StatusFilter>('all')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  async function load(nextCity = city) {
    setLoading(true); setError('')
    const result = await fetchCoverageSnapshot(supabase, nextCity)
    if (result.error || !result.snapshot) setError(result.error || 'Coverage snapshot is unavailable.')
    else setSnapshot(result.snapshot)
    setLoading(false)
  }

  useEffect(() => { void load(city) }, [city]) // eslint-disable-line react-hooks/exhaustive-deps

  const selectedCity = snapshot?.cities.find(item => item.city === city)
  const cells = useMemo(() => {
    const term = query.trim().toLowerCase()
    return (snapshot?.cells || []).filter(cell => {
      if (status !== 'all' && cell.coverage_status !== status) return false
      if (!term) return true
      return `${cell.category_name} ${cell.subcategory_name}`.toLowerCase().includes(term)
    })
  }, [snapshot, query, status])

  const categories = useMemo(() => {
    const result = new Map<string, { name: string; total: number; covered: number; candidates: number; empty: number }>()
    for (const cell of snapshot?.cells || []) {
      const current = result.get(cell.category_slug) || { name: cell.category_name, total: 0, covered: 0, candidates: 0, empty: 0 }
      current.total += 1
      if (cell.coverage_status === 'covered') current.covered += 1
      else if (cell.coverage_status === 'candidate_found') current.candidates += 1
      else current.empty += 1
      result.set(cell.category_slug, current)
    }
    return [...result.entries()].map(([slug, value]) => ({ slug, ...value })).sort((a, b) => b.empty - a.empty || a.name.localeCompare(b.name))
  }, [snapshot])

  return <section className="coverage-dashboard directory-page">
    <div className="coverage-heading">
      <span><Target size={14} /> STAFF COMMAND CENTER</span>
      <h1>Coverage intelligence.</h1>
      <p>Every city × category × business type, measured against first-presence coverage and the research queue.</p>
    </div>

    <div className="coverage-toolbar">
      <label><span>Market</span><select value={city} onChange={event => setCity(event.target.value)}>{(snapshot?.cities || []).map(item => <option key={`${item.city}-${item.state}`} value={item.city}>{item.city}, {item.state}</option>)}</select></label>
      <button onClick={() => void load()} disabled={loading}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
    </div>

    {error && <div className="coverage-error"><AlertTriangle size={18} /><span><strong>Coverage data unavailable.</strong>{error}</span></div>}

    <div className="coverage-kpis">
      <article><MapPinned /><span>City launch target</span><strong>{selectedCity?.city_launch_target || 0}</strong><small>{selectedCity?.published_business_slots || 0} publishable profiles classified into taxonomy cells</small></article>
      <article><CheckCircle2 /><span>Types covered</span><strong>{selectedCity?.target_met_cells || 0}<em>/441</em></strong><small>{selectedCity?.taxonomy_coverage_pct || 0}% taxonomy presence</small></article>
      <article><Search /><span>Candidates found</span><strong>{selectedCity?.candidate_found_cells || 0}</strong><small>{selectedCity?.candidate_slots || 0} candidate records routed into open types</small></article>
      <article><Database /><span>Enrichment queue</span><strong>{snapshot?.enrichment.pending || 0}</strong><small>{snapshot?.enrichment.complete || 0} location enrichments completed · {snapshot?.enrichment.manual || 0} manual</small></article>
    </div>

    <section className="coverage-category-health">
      <div className="coverage-section-title"><span>CATEGORY PRESSURE</span><h2>Where the directory is thinnest.</h2></div>
      <div className="coverage-category-grid">{categories.slice(0, 12).map(item => <article key={item.slug}><div><strong>{item.name}</strong><small>{item.covered}/{item.total} types covered</small></div><div className="coverage-mini-bar"><i style={{ width: `${Math.round((item.covered / Math.max(item.total, 1)) * 100)}%` }} /></div><span>{item.candidates} candidate types · {item.empty} empty</span></article>)}</div>
    </section>

    <section className="coverage-gap-table">
      <div className="coverage-section-title"><span>441-TYPE ACQUISITION CHECKLIST</span><h2>{city} gaps.</h2><p>Candidate found means research has supply waiting; empty means the system needs net-new discovery.</p></div>
      <div className="coverage-filters">
        <label className="coverage-search"><Search size={15} /><input value={query} onChange={event => setQuery(event.target.value)} placeholder="Search category or business type" /></label>
        <div>{(['all','empty','candidate_found','covered'] as StatusFilter[]).map(value => <button key={value} className={status === value ? 'active' : ''} onClick={() => setStatus(value)}>{value === 'candidate_found' ? 'Candidate found' : value === 'all' ? 'All' : value[0].toUpperCase() + value.slice(1)}</button>)}</div>
      </div>
      <div className="coverage-rows">
        {loading && !snapshot ? <div className="coverage-loading">Building the coverage matrix…</div> : cells.map(cell => <CoverageRow key={`${cell.city}:${cell.category_slug}:${cell.subcategory_slug}`} cell={cell} />)}
        {!loading && cells.length === 0 && <div className="coverage-loading">No coverage cells match this filter.</div>}
      </div>
    </section>

    <section className="coverage-system-note">
      <Target size={19} /><div><strong>Acquisition engine is connected.</strong><p>{snapshot?.gap_tasks.open_gap_tasks || 0} open city/type tasks are scored by launch priority and empty coverage. Existing candidates are reprioritized into the same system automatically.</p></div>
    </section>
  </section>
}

function CoverageRow({ cell }: { cell: CoverageCell }) {
  return <article className={`coverage-row status-${cell.coverage_status}`}>
    <div className="coverage-row-main"><span>{cell.category_name}</span><strong>{cell.subcategory_name}</strong><small>Long-term saturation target: {cell.saturation_target}</small></div>
    <div className="coverage-row-counts"><span><strong>{cell.published_count}</strong> live</span><span><strong>{cell.candidate_count}</strong> candidates</span></div>
    <div className="coverage-status"><i />{cell.coverage_status === 'covered' ? 'Covered' : cell.coverage_status === 'candidate_found' ? 'Candidate found' : 'Discovery needed'}</div>
    <ChevronRight size={16} />
  </article>
}
