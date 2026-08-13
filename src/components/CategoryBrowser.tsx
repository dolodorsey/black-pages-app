import { ChevronRight, Grid2X2, Search } from 'lucide-react'
import { pluralize } from '../lib/categories.ts'
import { countBySubcategory, type CategoryCount, type DirectoryBusiness } from '../services/directory.ts'
import { subcategoriesFor, type TaxonomyCategory, type TaxonomySubcategory } from '../services/taxonomy.ts'

function categoryGlyph(key: string) {
  if (key.includes('food')) return '🍽'
  if (key.includes('beauty')) return '✦'
  if (key.includes('nightlife')) return '◐'
  if (key.includes('retail') || key.includes('fashion')) return '◆'
  if (key.includes('culture') || key.includes('creative')) return '◈'
  if (key.includes('fitness')) return '▲'
  if (key.includes('technology')) return '⌘'
  if (key.includes('legal')) return '§'
  if (key.includes('real-estate')) return '⌂'
  if (key.includes('construction') || key.includes('home')) return '▰'
  return '●'
}

export function CategoryBrowser({ businesses, taxonomyCategories, taxonomySubcategories, counts, onBrowse }: {
  businesses: readonly DirectoryBusiness[]
  taxonomyCategories: readonly TaxonomyCategory[]
  taxonomySubcategories: readonly TaxonomySubcategory[]
  counts: readonly CategoryCount[]
  onBrowse: (category: string, subcategory?: string) => void
}) {
  const categoryTotals = new Map(counts)
  return <section className="categories-screen directory-page">
    <div className="directory-page-heading">
      <span><Grid2X2 size={14} /> MASTER BUSINESS INDEX</span>
      <h1>Browse every business category.</h1>
      <p>{pluralize(taxonomyCategories.length, 'category', 'categories')} with hundreds of specific business types. Categories remain available as national coverage grows.</p>
      <button className="directory-heading-action" onClick={() => onBrowse('all', 'all')}><Search size={16} /> Search all businesses</button>
    </div>

    <div className="category-directory-list">
      {taxonomyCategories.map(category => {
        const masterSubcategories = subcategoriesFor(taxonomySubcategories, category.slug)
        const liveCounts = new Map(countBySubcategory(businesses, category.slug))
        const liveSubcategories = masterSubcategories.filter(item => (liveCounts.get(item.slug) || 0) > 0)
        const count = categoryTotals.get(category.slug) || 0
        return <article className="category-directory-card" key={category.slug}>
          <button className="category-directory-header" onClick={() => onBrowse(category.slug, 'all')}>
            <span className="category-directory-icon">{categoryGlyph(category.slug)}</span>
            <span className="category-directory-copy"><strong>{category.name}</strong><small>{pluralize(count, 'business', 'businesses')} · {pluralize(masterSubcategories.length, 'type')}</small></span>
            <span className="category-view-all">View all <ChevronRight size={17} /></span>
          </button>
          {liveSubcategories.length > 0
            ? <div className="subcategory-grid" aria-label={`${category.name} subcategories`}>
                {liveSubcategories.map(item => <button key={item.slug} onClick={() => onBrowse(category.slug, item.slug)}>
                  <span>{item.name}</span><small>{liveCounts.get(item.slug) || 0}</small>
                </button>)}
              </div>
            : <div className="subcategory-empty"><strong>Listings coming soon</strong>Business types stay indexed behind the scenes and appear here as coverage is added.</div>}
        </article>
      })}
    </div>
  </section>
}

export function SubcategoryFilterRail({ subcategories, liveCounts, subcategory, onSubcategoryChange }: {
  subcategories: readonly TaxonomySubcategory[]
  liveCounts: ReadonlyMap<string, number>
  subcategory: string
  onSubcategoryChange: (value: string) => void
}) {
  const visibleSubcategories = subcategories.filter(item => (liveCounts.get(item.slug) || 0) > 0 || item.slug === subcategory)
  if (visibleSubcategories.length === 0) return null
  return <div className="filter-rail subcategory-filter-rail" aria-label="Business type filter">
    <button className={subcategory === 'all' ? 'active' : ''} onClick={() => onSubcategoryChange('all')}>All types</button>
    {visibleSubcategories.map(item => <button className={subcategory === item.slug ? 'active' : ''} key={item.slug} onClick={() => onSubcategoryChange(item.slug)}>
      {item.name} <small>{liveCounts.get(item.slug) || 0}</small>
    </button>)}
  </div>
}
