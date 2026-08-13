import { useMemo, useState } from 'react'
import { ChevronDown, ChevronRight, Grid2X2, Search, X } from 'lucide-react'
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
  const [taxonomyQuery, setTaxonomyQuery] = useState('')
  const [expandedCategories, setExpandedCategories] = useState<Set<string>>(new Set())
  const categoryTotals = new Map(counts)
  const needle = taxonomyQuery.trim().toLowerCase()

  const visibleCategories = useMemo(() => taxonomyCategories.filter(category => {
    if (!needle) return true
    if (category.name.toLowerCase().includes(needle)) return true
    return subcategoriesFor(taxonomySubcategories, category.slug).some(item => item.name.toLowerCase().includes(needle))
  }), [needle, taxonomyCategories, taxonomySubcategories])

  function toggleExpanded(slug: string) {
    setExpandedCategories(current => {
      const next = new Set(current)
      if (next.has(slug)) next.delete(slug)
      else next.add(slug)
      return next
    })
  }

  return <section className="categories-screen directory-page">
    <div className="directory-page-heading">
      <span><Grid2X2 size={14} /> MASTER BUSINESS INDEX</span>
      <h1>Browse every business category.</h1>
      <p>{pluralize(taxonomyCategories.length, 'category', 'categories')} with {pluralize(taxonomySubcategories.length, 'specific business type')}. The full taxonomy stays visible as national coverage grows.</p>
      <button className="directory-heading-action" onClick={() => onBrowse('all', 'all')}><Search size={16} /> Search all businesses</button>
    </div>

    <div className="taxonomy-search-wrap">
      <Search size={18} />
      <input value={taxonomyQuery} onChange={event => setTaxonomyQuery(event.target.value)} placeholder="Search categories or business types" aria-label="Search categories and business types" />
      {taxonomyQuery && <button aria-label="Clear category search" onClick={() => setTaxonomyQuery('')}><X size={16} /></button>}
    </div>

    <div className="category-directory-list">
      {visibleCategories.map(category => {
        const masterSubcategories = subcategoriesFor(taxonomySubcategories, category.slug)
        const liveCounts = new Map(countBySubcategory(businesses, category.slug))
        const filteredSubcategories = needle
          ? masterSubcategories.filter(item => item.name.toLowerCase().includes(needle) || category.name.toLowerCase().includes(needle))
          : masterSubcategories
        const expanded = expandedCategories.has(category.slug) || Boolean(needle)
        const shownSubcategories = expanded ? filteredSubcategories : filteredSubcategories.slice(0, 8)
        const count = categoryTotals.get(category.slug) || 0
        return <article className="category-directory-card" key={category.slug}>
          <button className="category-directory-header" onClick={() => onBrowse(category.slug, 'all')}>
            <span className="category-directory-icon">{categoryGlyph(category.slug)}</span>
            <span className="category-directory-copy"><strong>{category.name}</strong><small>{pluralize(count, 'business', 'businesses')} · {pluralize(masterSubcategories.length, 'type')}</small></span>
            <span className="category-view-all">View all <ChevronRight size={17} /></span>
          </button>

          {shownSubcategories.length > 0
            ? <>
                <div className="subcategory-grid" aria-label={`${category.name} subcategories`}>
                  {shownSubcategories.map(item => {
                    const liveCount = liveCounts.get(item.slug) || 0
                    return <button className={liveCount === 0 ? 'empty-type' : ''} key={item.slug} onClick={() => onBrowse(category.slug, item.slug)}>
                      <span>{item.name}</span><small>{liveCount}</small>
                    </button>
                  })}
                </div>
                {!needle && filteredSubcategories.length > 8 && <button className="subcategory-expand" onClick={() => toggleExpanded(category.slug)}>
                  {expanded ? 'Show fewer types' : `Show all ${filteredSubcategories.length} types`} <ChevronDown className={expanded ? 'expanded' : ''} size={15} />
                </button>}
              </>
            : <div className="subcategory-empty"><strong>No matching business types</strong>Try a broader category search.</div>}
        </article>
      })}
      {visibleCategories.length === 0 && <div className="taxonomy-no-results"><Search size={22} /><strong>No category matches</strong><span>Try a broader business type or category name.</span></div>}
    </div>
  </section>
}

export function SubcategoryFilterRail({ subcategories, liveCounts, subcategory, onSubcategoryChange }: {
  subcategories: readonly TaxonomySubcategory[]
  liveCounts: ReadonlyMap<string, number>
  subcategory: string
  onSubcategoryChange: (value: string) => void
}) {
  if (subcategories.length === 0) return null
  return <div className="filter-rail subcategory-filter-rail" aria-label="Business type filter">
    <button className={subcategory === 'all' ? 'active' : ''} onClick={() => onSubcategoryChange('all')}>All types</button>
    {subcategories.map(item => {
      const count = liveCounts.get(item.slug) || 0
      return <button className={`${subcategory === item.slug ? 'active' : ''} ${count === 0 ? 'empty-type' : ''}`.trim()} key={item.slug} onClick={() => onSubcategoryChange(item.slug)}>
        {item.name} <small>{count}</small>
      </button>
    })}
  </div>
}