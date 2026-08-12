import { Bookmark, ExternalLink, MapPin, Phone, Store } from 'lucide-react'
import { labelCategory, labelSubcategory } from '../lib/categories'
import type { DirectoryBusiness } from '../services/directory'
import { Rating, StatusBadge } from './primitives'

export function BusinessCard({ business, saved, onOpen, onSave, compact = false }: {
  business: DirectoryBusiness
  saved: boolean
  onOpen: () => void
  onSave: () => void
  compact?: boolean
}) {
  const categoryLine = business.subcategory
    ? `${labelCategory(business.category)} · ${labelSubcategory(business.subcategory)}`
    : labelCategory(business.category)

  return <article className={`business-card ${compact ? 'compact' : ''}`} onClick={onOpen}>
    <div className="business-image">
      {business.image_url ? <img src={business.image_url} alt="" loading="lazy" /> : <div className="image-fallback"><Store /></div>}
      <div className="image-shade" />
      <button className={`save-button ${saved ? 'saved' : ''}`} aria-label={saved ? 'Remove from saved' : 'Save business'} onClick={event => { event.stopPropagation(); onSave() }}>
        <Bookmark size={17} fill={saved ? 'currentColor' : 'none'} />
      </button>
      <StatusBadge business={business} />
    </div>
    <div className="business-copy">
      <div className="card-meta"><span>{categoryLine}</span><Rating business={business} /></div>
      <h3>{business.business_name}</h3>
      <p>{business.short_description || `${labelCategory(business.category)} in ${business.neighborhood || business.city}.`}</p>
      <div className="location-line"><MapPin size={13} /> {business.neighborhood ? `${business.neighborhood}, ` : ''}{business.city}{business.state ? `, ${business.state}` : ''}</div>
      <div className="business-card-actions" onClick={event => event.stopPropagation()}>
        {business.phone && <a href={`tel:${business.phone}`}><Phone size={14} /> Call</a>}
        {business.website_url && <a href={business.website_url} target="_blank" rel="noreferrer"><ExternalLink size={14} /> Website</a>}
        <button onClick={onOpen}>View details</button>
      </div>
    </div>
  </article>
}
