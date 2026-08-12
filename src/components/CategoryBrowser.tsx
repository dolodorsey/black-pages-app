import { ChevronRight, Layers3 } from 'lucide-react'
import { labelCategory, labelSubcategory, pluralize } from '../lib/categories'
import {
  countBySubcategory,
  type CategoryCount,
  type DirectoryBusiness,
  type SubcategoryCount,
} from '../services/directory'

function categoryGlyph(key: string) {
  if (key === 'restaurant' || key === 'brunch' || key === 'food_truck') return '🍽'
  if (key === 'beauty' || key === 'spa' || key === 'wellness') return '✦'
  if (key === 'nightclub' || key === 'nightlife' || key === 'lounge' || key === 'hookah') return '◐'
  if (key === 'shopping') return '◆'
  if (key === 'culture' || key === 'jazz' || key === 'comedy') return '◈'
  if (key === 'fitness') return '▲'
  return '●'
}

/** Dedicated category directory with all live subcategories nested beneath each category. */
export function CategoryBrowser({ businesses, categories, onBrowse }: {
  businesses: readonly DirectoryBusiness[]
  categories: readonly CategoryCount[]
  onBrowse: (category: string, subcategory?: string) => void
}) {
  return <section className="categories-screen">
    <div className="screen-heading categories-heading">
      <span><Layers3 size={13} /> CATEGORIES</span>
      <h1>Browse everything.</h1>
      <p>Choose a category, then drill into the exact type of Black-owned business you need.</p>
    </div>

    <div className="category-directory-list">
      {categories.map(([key, count]) => {
        const subcategories = countBySubcategory(businesses, key)
        return <article className="category-directory-card" key={key}>
          <button className="category-directory-header" onClick={() => onBrowse(key, 'all')}>
            <span className="category-directory-icon">{categoryGlyph(key)}</span>
            <span className="category-directory-copy">
              <strong>{labelCategory(key)}</strong>
              <small>{pluralize(count, 'business', 'businesses')} · {pluralize(subcategories.length, 'subcategory', 'subcategories')}</small>
            </span>
            <ChevronRight size={19} />
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

/** Secondary discover filter shown after a parent category is selected. */
export function SubcategoryFilterRail({ subcategories, subcategory, onSubcategoryChange }: {
  subcategories: readonly SubcategoryCount[]
  subcategory: string
  onSubcategoryChange: (value: string) => void
}) {
  if (subcategories.length === 0) return null
  return <div className="filter-rail subcategory-filter-rail" aria-label="Subcategory filter">
    <button className={subcategory === 'all' ? 'active' : ''} onClick={() => onSubcategoryChange('all')}>All types</button>
    {subcategories.map(([key, count]) => <button className={subcategory === key ? 'active' : ''} key={key} onClick={() => onSubcategoryChange(key)}>
      {labelSubcategory(key)} <small>{count}</small>
    </button>)}
  </div>
}
