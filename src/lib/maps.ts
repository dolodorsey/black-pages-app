import type { DirectoryBusiness } from '../services/directory'

/** Google Maps deep link: coordinates when known, otherwise a name search. */
export function mapsUrl(business: DirectoryBusiness) {
  if (business.latitude != null && business.longitude != null) {
    return `https://www.google.com/maps/search/?api=1&query=${business.latitude},${business.longitude}`
  }
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${business.business_name} ${business.address || business.city}`)}`
}
