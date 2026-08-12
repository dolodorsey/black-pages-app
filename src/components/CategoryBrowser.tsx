import { ChevronRight, Grid2X2, Search } from 'lucide-react'
import { labelCategory, labelSubcategory, pluralize } from '../lib/categories'
import {
  countBySubcategory,
  type CategoryCount,
  type DirectoryBusiness,
  type SubcategoryCount,
} from '../services/directory'

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

/** Full business-category index with nested subcategories. */
export function CategoryBrowser({ businesses, categories, onBrowse }: {
  businesses: readonly DirectoryBusiness[]
  categories: readonly CategoryCount[]
  onBrowse: (category: string, subcategory?: string) => void
}) {
  return <section className="categories-screen directory-page">
    <div className="directory-page-heading">
      <span><Grid2X2 size={14} /> BUSINESS CATEGORIES</span>
      <h1>Browse by category.</h1>
      <p>Start broad, then narrow to the exact business type you need.</p>
      <button className="directory-heading-action" onClick={() => onBrowse('all', 'all')}><Search size={16} /> Search all businesses</button>
    </div>

    <div className="category-directory-list">
      {categories.map(([key, count]) => {
        const subcategories = countBySubcategory(businesses, key)
        return <article className="category-directory-card" key={key}>
          <button className="category-directory-header" onClick={() => onBrowse(key, 'all')}>
            <span className="category-directory-icon">{categoryGlyph(key)}</span>
            <span className="category-directory-copy">
              <strong>{labelCategory(key)}</strong>
              <small>{pluralize(count, 'business', 'businesses')}</small>
            </span>
            <span className="category-view-all">View all <ChevronRight size={17} /></span>
          </button>

          {subcategories.length > 0 && <div className="subcategory-grid" aria-label={`${labelCategory(key)} subcategories`}>
            {subcategories.map(([subcategory, subCount]) => <button key={subcategory} onClick={() => onBrowse(key, subcategory)}>
              <span>{labelSubcategory(subcategory)}</span>
              <small>{subCount}</small>
            </button>)}
          </div>}
        </article>
      })}
    </div>
  </section>
}

export function SubcategoryFilterRail({ subcategories, subcategory, onSubcategoryChange }: {
  subcategories: readonly SubcategoryCount[]
  subcategory: string
  onSubcategoryChange: (value: string) => void
}) {
  if (subcategories.length === 0) return null
  return <div className="filter-rail subcategory-filter-rail" aria-label="Business type filter">
    <button className={subcategory === 'all' ? 'active' : ''} onClick={() => onSubcategoryChange('all')}>All types</button>
    {subcategories.map(([key, count]) => <button className={subcategory === key ? 'active' : ''} key={key} onClick={() => onSubcategoryChange(key)}>
      {labelSubcategory(key)} <small>{count}</small>
    </button>)}
  </div>
}
