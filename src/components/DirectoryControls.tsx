import { ChevronRight, MapPin, Search, X } from 'lucide-react'
import { labelCategory } from '../lib/categories'
import type { CategoryCount } from '../services/directory'

/** White-Pages-style business/service + location search. */
export function DirectorySearchPanel({
  query,
  location,
  onQueryChange,
  onLocationChange,
  onSubmit,
  compact = false,
}: {
  query: string
  location: string
  onQueryChange: (value: string) => void
  onLocationChange: (value: string) => void
  onSubmit: () => void
  compact?: boolean
}) {
  return <form className={`directory-search-panel ${compact ? 'compact' : ''}`} onSubmit={event => { event.preventDefault(); onSubmit() }}>
    <label className="directory-field">
      <Search size={18} />
      <span>
        <small>WHAT</small>
        <input value={query} onChange={event => onQueryChange(event.target.value)} placeholder="Business, service, or category" />
      </span>
      {query && <button type="button" aria-label="Clear business search" onClick={() => onQueryChange('')}><X size={15} /></button>}
    </label>
    <label className="directory-field">
      <MapPin size={18} />
      <span>
        <small>WHERE</small>
        <input value={location} onChange={event => onLocationChange(event.target.value)} placeholder="City, state, or neighborhood" />
      </span>
      {location && <button type="button" aria-label="Clear location" onClick={() => onLocationChange('')}><X size={15} /></button>}
    </label>
    <button className="directory-search-submit" type="submit"><Search size={17} /> Search</button>
  </form>
}

export function CategoryFilterRail({ categories, category, onCategoryChange }: {
  categories: readonly CategoryCount[]
  category: string
  onCategoryChange: (value: string) => void
}) {
  return <div className="filter-rail directory-filter-rail" aria-label="Business category filter">
    <button className={category === 'all' ? 'active' : ''} onClick={() => onCategoryChange('all')}>All businesses</button>
    {categories.map(([key, count]) => <button className={category === key ? 'active' : ''} key={key} onClick={() => onCategoryChange(key)}>
      {labelCategory(key)} <small>{count}</small>
    </button>)}
  </div>
}

function categoryGlyph(key: string) {
  const value = key.toLowerCase()
  if (value.includes('restaurant') || value.includes('brunch') || value.includes('food')) return '🍽'
  if (value.includes('beauty') || value.includes('spa') || value.includes('wellness')) return '✦'
  if (value.includes('nightclub') || value.includes('lounge') || value.includes('bar')) return '◐'
  if (value.includes('shop') || value.includes('retail')) return '◆'
  if (value.includes('culture') || value.includes('jazz') || value.includes('comedy')) return '◈'
  if (value.includes('fitness')) return '▲'
  if (value.includes('business') || value.includes('professional')) return '▣'
  return '●'
}

/** Home-screen category shortcuts: useful, compact, and business-only. */
export function CategoryRail({ categories, onSelectCategory, onSeeAll }: {
  categories: readonly CategoryCount[]
  onSelectCategory: (value: string) => void
  onSeeAll: () => void
}) {
  return <section className="section-block directory-category-section">
    <div className="section-title">
      <div><span>BROWSE</span><h2>Business categories</h2><p>Find the type of business you need.</p></div>
      <button onClick={onSeeAll}>All categories <ChevronRight size={15} /></button>
    </div>
    <div className="category-rail">
      {categories.slice(0, 8).map(([key, count]) => <button key={key} onClick={() => onSelectCategory(key)}>
        <span className="category-icon">{categoryGlyph(key)}</span>
        <strong>{labelCategory(key)}</strong><small>{count} {count === 1 ? 'business' : 'businesses'}</small>
      </button>)}
    </div>
  </section>
}
