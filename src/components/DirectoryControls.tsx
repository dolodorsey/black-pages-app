import { ChevronRight, LocateFixed, Search, X } from 'lucide-react'
import { labelCategory } from '../lib/categories'
import type { CategoryCount } from '../services/directory'

/** Home-screen search bar that hands off to the discover tab. */
export function FloatingSearch({ query, onQueryChange, onFocus, onUseLocation }: {
  query: string
  onQueryChange: (value: string) => void
  onFocus: () => void
  onUseLocation: () => void
}) {
  return <section className="floating-search">
    <Search size={19} />
    <input value={query} onChange={event => onQueryChange(event.target.value)} onFocus={onFocus} placeholder="What are you looking for?" />
    <button aria-label="Use my location" onClick={onUseLocation}><LocateFixed size={18} /></button>
  </section>
}

/** Discover-screen search field with a clear button. */
export function DirectorySearch({ query, onQueryChange }: {
  query: string
  onQueryChange: (value: string) => void
}) {
  return <div className="directory-search"><Search size={19} /><input autoFocus value={query} onChange={event => onQueryChange(event.target.value)} placeholder="Business, food, beauty, service, neighborhood…" />{query && <button onClick={() => onQueryChange('')}><X size={17} /></button>}</div>
}

/** Discover-screen category chips. */
export function CategoryFilterRail({ categories, category, onCategoryChange }: {
  categories: readonly CategoryCount[]
  category: string
  onCategoryChange: (value: string) => void
}) {
  return <div className="filter-rail"><button className={category === 'all' ? 'active' : ''} onClick={() => onCategoryChange('all')}>All</button>{categories.map(([key, count]) => <button className={category === key ? 'active' : ''} key={key} onClick={() => onCategoryChange(key)}>{labelCategory(key)} <small>{count}</small></button>)}</div>
}

function categoryGlyph(key: string) {
  if (key === 'restaurant' || key === 'brunch') return '🍽'
  if (key === 'beauty' || key === 'spa') return '✦'
  if (key === 'nightclub' || key === 'lounge') return '◐'
  if (key === 'shopping') return '◆'
  return '●'
}

/** Home-screen "browse by category" block. */
export function CategoryRail({ categories, onSelectCategory, onSeeAll }: {
  categories: readonly CategoryCount[]
  onSelectCategory: (value: string) => void
  onSeeAll: () => void
}) {
  return <section className="section-block">
    <div className="section-title"><div><span>EXPLORE</span><h2>Browse by category</h2></div><button onClick={onSeeAll}>See all <ChevronRight size={15} /></button></div>
    <div className="category-rail">
      {categories.slice(0, 10).map(([key, count]) => <button key={key} onClick={() => onSelectCategory(key)}>
        <span className="category-icon">{categoryGlyph(key)}</span>
        <strong>{labelCategory(key)}</strong><small>{count} businesses</small>
      </button>)}
    </div>
  </section>
}
