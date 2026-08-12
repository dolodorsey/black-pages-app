import { ChevronRight, LocateFixed, MapPin, Search, X } from 'lucide-react'
import type { CategoryCount } from '../services/directory.ts'
import type { TaxonomyCategory } from '../services/taxonomy.ts'

function countMap(counts: readonly CategoryCount[]) {
  return new Map(counts)
}

/** White-Pages-style WHAT + WHERE + near-me search. */
export function DirectorySearchPanel({ query, location, onQueryChange, onLocationChange, onSubmit, onUseMyLocation, nearActive = false, onClearNear, compact = false }: {
  query: string
  location: string
  onQueryChange: (value: string) => void
  onLocationChange: (value: string) => void
  onSubmit: () => void
  onUseMyLocation?: () => void
  nearActive?: boolean
  onClearNear?: () => void
  compact?: boolean
}) {
  return <form className={`directory-search-panel ${compact ? 'compact' : ''}`} onSubmit={event => { event.preventDefault(); onSubmit() }}>
    <label className="directory-field">
      <Search size={18} />
      <span><small>WHAT</small><input value={query} onChange={event => onQueryChange(event.target.value)} placeholder="Business, service, or category" /></span>
      {query && <button type="button" aria-label="Clear business search" onClick={() => onQueryChange('')}><X size={15} /></button>}
    </label>
    <label className="directory-field">
      <MapPin size={18} />
      <span><small>WHERE</small><input value={location} onChange={event => onLocationChange(event.target.value)} placeholder="City, state, neighborhood, or ZIP" /></span>
      {location && <button type="button" aria-label="Clear location" onClick={() => onLocationChange('')}><X size={15} /></button>}
    </label>
    {onUseMyLocation && <button className={`directory-near-me ${nearActive ? 'active' : ''}`} type="button" onClick={nearActive && onClearNear ? onClearNear : onUseMyLocation}>
      {nearActive ? <X size={16} /> : <LocateFixed size={16} />} {nearActive ? 'Clear near me' : 'Near me'}
    </button>}
    <button className="directory-search-submit" type="submit"><Search size={17} /> Search</button>
  </form>
}

export function CategoryFilterRail({ taxonomyCategories, counts, category, onCategoryChange }: {
  taxonomyCategories: readonly TaxonomyCategory[]
  counts: readonly CategoryCount[]
  category: string
  onCategoryChange: (value: string) => void
}) {
  const totals = countMap(counts)
  return <div className="filter-rail directory-filter-rail" aria-label="Business category filter">
    <button className={category === 'all' ? 'active' : ''} onClick={() => onCategoryChange('all')}>All businesses</button>
    {taxonomyCategories.map(item => <button className={category === item.slug ? 'active' : ''} key={item.slug} onClick={() => onCategoryChange(item.slug)}>
      {item.name} <small>{totals.get(item.slug) || 0}</small>
    </button>)}
  </div>
}

function categoryGlyph(key: string) {
  const value = key.toLowerCase()
  if (value.includes('food')) return '🍽'
  if (value.includes('beauty') || value.includes('wellness')) return '✦'
  if (value.includes('nightlife')) return '◐'
  if (value.includes('retail') || value.includes('fashion')) return '◆'
  if (value.includes('culture') || value.includes('creative')) return '◈'
  if (value.includes('fitness') || value.includes('sports')) return '▲'
  if (value.includes('technology')) return '⌘'
  if (value.includes('legal')) return '§'
  if (value.includes('real-estate')) return '⌂'
  if (value.includes('construction') || value.includes('home')) return '▰'
  if (value.includes('business') || value.includes('professional')) return '▣'
  return '●'
}

export function CategoryRail({ taxonomyCategories, counts, onSelectCategory, onSeeAll }: {
  taxonomyCategories: readonly TaxonomyCategory[]
  counts: readonly CategoryCount[]
  onSelectCategory: (value: string) => void
  onSeeAll: () => void
}) {
  const totals = countMap(counts)
  const ranked = [...taxonomyCategories].sort((a, b) => (totals.get(b.slug) || 0) - (totals.get(a.slug) || 0) || a.sort_order - b.sort_order)
  return <section className="section-block directory-category-section">
    <div className="section-title"><div><span>BROWSE</span><h2>Business categories</h2><p>32 master categories and hundreds of business types.</p></div><button onClick={onSeeAll}>All categories <ChevronRight size={15} /></button></div>
    <div className="category-rail">
      {ranked.slice(0, 10).map(item => <button key={item.slug} onClick={() => onSelectCategory(item.slug)}>
        <span className="category-icon">{categoryGlyph(item.slug)}</span>
        <strong>{item.name}</strong><small>{totals.get(item.slug) || 0} {(totals.get(item.slug) || 0) === 1 ? 'business' : 'businesses'}</small>
      </button>)}
    </div>
  </section>
}
