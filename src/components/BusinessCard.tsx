import { Bookmark, MapPin, Store } from 'lucide-react'
import { labelCategory } from '../lib/categories'
import type { DirectoryBusiness } from '../services/directory'
import { Rating, StatusBadge } from './primitives'

export function BusinessCard({ business, saved, onOpen, onSave, compact = false }: {
  business: DirectoryBusiness
  saved: boolean
  onOpen: () => void
  onSave: () => void
  compact?: boolean
}) {
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
      <div className="card-meta"><span>{labelCategory(business.category)}</span><Rating business={business} /></div>
      <h3>{business.business_name}</h3>
      <p>{business.short_description || `${labelCategory(business.category)} in ${business.neighborhood || business.city}.`}</p>
      <div className="location-line"><MapPin size={13} /> {business.neighborhood ? `${business.neighborhood}, ` : ''}{business.city}</div>
    </div>
  </article>
}
