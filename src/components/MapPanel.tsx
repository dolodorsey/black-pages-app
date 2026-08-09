import { LocateFixed, MapPin, Search } from 'lucide-react'
import type { DirectoryBusiness } from '../services/directory'
import { BusinessCard } from './BusinessCard'

/**
 * Map tab. The embedded OpenStreetMap frame is unchanged from the monolithic
 * App; replacing it with an interactive map is a later phase.
 */
export function MapPanel({ query, onQueryChange, mapReady, savedIds, onOpen, onSave }: {
  query: string
  onQueryChange: (value: string) => void
  mapReady: readonly DirectoryBusiness[]
  savedIds: readonly string[]
  onOpen: (business: DirectoryBusiness) => void
  onSave: (directoryId: string) => void
}) {
  return <section className="map-screen">
    <div className="map-canvas">
      <iframe title="Black Pages business map" src="https://www.openstreetmap.org/export/embed.html?bbox=-84.58%2C33.62%2C-84.18%2C33.94&layer=mapnik" />
      <div className="map-shade" />
      <div className="map-search"><Search size={17} /><input value={query} onChange={event => onQueryChange(event.target.value)} placeholder="Search this area" /></div>
      <button className="recenter"><LocateFixed size={18} /></button>
      <div className="map-counter"><MapPin size={14} /> {mapReady.length} map-ready businesses</div>
    </div>
    <div className="map-results">
      <div className="section-title"><div><span>NEAR ATLANTA</span><h2>Explore the map</h2></div></div>
      <div className="horizontal-cards">{mapReady.slice(0, 20).map(business => <BusinessCard compact key={business.directory_id} business={business} saved={savedIds.includes(business.directory_id)} onOpen={() => onOpen(business)} onSave={() => onSave(business.directory_id)} />)}</div>
    </div>
  </section>
}
