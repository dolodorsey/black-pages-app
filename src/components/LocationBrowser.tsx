import { ChevronRight, MapPin } from 'lucide-react'
import { pluralize } from '../lib/categories.ts'
import type { LocationGroup } from '../services/directory.ts'

export function LocationBrowser({ locations, onSelectLocation, limit = 8 }: {
  locations: readonly LocationGroup[]
  onSelectLocation: (value: string) => void
  limit?: number
}) {
  const visible = locations.slice(0, limit)
  if (visible.length === 0) return null

  return <section className="location-browser section-block">
    <div className="section-title">
      <div><span>LOCATIONS</span><h2>Browse Black-owned businesses by city.</h2><p>Then narrow to a neighborhood or ZIP code.</p></div>
    </div>
    <div className="location-city-grid">
      {visible.map(location => <article className="location-city-card" key={location.key}>
        <button className="location-city-main" onClick={() => onSelectLocation(`${location.city} ${location.state}`.trim())}>
          <span className="location-pin"><MapPin size={17} /></span>
          <span><strong>{location.city}{location.state ? `, ${location.state}` : ''}</strong><small>{pluralize(location.count, 'business', 'businesses')}</small></span>
          <ChevronRight size={17} />
        </button>
        {(location.neighborhoods.length > 0 || location.postalCodes.length > 0) && <div className="location-drilldown">
          {location.neighborhoods.slice(0, 5).map(neighborhood => <button key={neighborhood} onClick={() => onSelectLocation(`${neighborhood} ${location.city} ${location.state}`.trim())}>{neighborhood}</button>)}
          {location.postalCodes.slice(0, 5).map(zip => <button className="zip-chip" key={zip} onClick={() => onSelectLocation(zip)}>{zip}</button>)}
        </div>}
      </article>)}
    </div>
  </section>
}
