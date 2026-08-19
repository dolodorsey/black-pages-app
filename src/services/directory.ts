/** Typed data access and trust-first matching for the Resource Exchange directory runtime. */
import type { SupabaseClient } from '@supabase/supabase-js'
import { labelCategory, labelSubcategory, taxonomyKey } from '../lib/categories.ts'
import type { Database, DirectoryRow, Json } from '../lib/database.types.ts'

export type TypedSupabaseClient = SupabaseClient<Database>

export type DirectoryBusiness = {
  directory_id: string
  source_type: string
  source_id: string
  business_name: string
  slug: string
  category: string
  subcategory: string | null
  city: string
  state: string
  neighborhood: string | null
  address: string | null
  postal_code: string | null
  short_description: string | null
  website_url: string | null
  instagram_handle: string | null
  phone: string | null
  business_email: string | null
  image_url: string | null
  latitude: number | null
  longitude: number | null
  rating: number | null
  review_count: number | null
  price_range: string | null
  featured: boolean
  ownership_status: string
  owner_verified: boolean
  tags: string[]
  hours: Json | null
  service_area: string | null
  specialties: string[]
  facebook_url: string | null
  linkedin_url: string | null
  tiktok_url: string | null
  serves_customers_at_location: boolean
  service_radius_miles: number | null
}

export type CategoryCount = readonly [category: string, count: number]
export type SubcategoryCount = readonly [subcategory: string, count: number]
export type DirectorySort = 'recommended' | 'az' | 'distance'
export type GeoPoint = { latitude: number; longitude: number }

export type DirectoryFilter = {
  category: string
  subcategory?: string
  query: string
  location?: string
  sort?: DirectorySort
  near?: GeoPoint | null
  maxDistanceMiles?: number
}

export type LocationGroup = {
  key: string
  city: string
  state: string
  count: number
  neighborhoods: string[]
  postalCodes: string[]
}

const EVENT_ONLY_SUBCATEGORIES = new Set(['event-series'])

function toNullableNumber(value: number | string | null | undefined): number | null {
  if (value === null || value === undefined || value === '') return null
  const parsed = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(parsed) ? parsed : null
}
function toText(value: string | null | undefined): string { return typeof value === 'string' ? value : '' }

export function normalizeDirectoryRow(row: DirectoryRow): DirectoryBusiness {
  return {
    directory_id: toText(row.directory_id), source_type: toText(row.source_type), source_id: toText(row.source_id),
    business_name: toText(row.business_name), slug: toText(row.slug), category: toText(row.category), subcategory: row.subcategory ?? null,
    city: toText(row.city), state: toText(row.state), neighborhood: row.neighborhood ?? null, address: row.address ?? null,
    postal_code: row.postal_code ?? null, short_description: row.short_description ?? null, website_url: row.website_url ?? null,
    instagram_handle: row.instagram_handle ?? null, phone: row.phone ?? null, business_email: row.business_email ?? null,
    image_url: row.image_url ?? null, latitude: toNullableNumber(row.latitude), longitude: toNullableNumber(row.longitude),
    rating: toNullableNumber(row.rating), review_count: toNullableNumber(row.review_count), price_range: row.price_range ?? null,
    featured: row.featured === true, ownership_status: toText(row.ownership_status), owner_verified: row.owner_verified === true,
    tags: Array.isArray(row.tags) ? row.tags.filter((tag): tag is string => typeof tag === 'string' && tag.length > 0) : [],
    hours: row.hours ?? null, service_area: row.service_area ?? null,
    specialties: Array.isArray(row.specialties) ? row.specialties.filter((item): item is string => typeof item === 'string' && item.length > 0) : [],
    facebook_url: row.facebook_url ?? null, linkedin_url: row.linkedin_url ?? null, tiktok_url: row.tiktok_url ?? null,
    serves_customers_at_location: row.serves_customers_at_location !== false, service_radius_miles: row.service_radius_miles ?? null,
  }
}

export function normalizeDirectoryRows(rows: DirectoryRow[] | null | undefined): DirectoryBusiness[] { return (rows ?? []).map(normalizeDirectoryRow) }
export function isBusinessListing(business: DirectoryBusiness): boolean { return !EVENT_ONLY_SUBCATEGORIES.has(taxonomyKey(business.subcategory)) }

export function countByCategory(businesses: readonly DirectoryBusiness[]): CategoryCount[] {
  const counts = new Map<string, number>()
  businesses.forEach(business => counts.set(business.category, (counts.get(business.category) || 0) + 1))
  return [...counts.entries()].sort((a, b) => b[1] - a[1] || labelCategory(a[0]).localeCompare(labelCategory(b[0])))
}
export function countBySubcategory(businesses: readonly DirectoryBusiness[], category = 'all'): SubcategoryCount[] {
  const counts = new Map<string, number>()
  businesses.forEach(business => { if (category !== 'all' && business.category !== category) return; const key = taxonomyKey(business.subcategory); if (key) counts.set(key, (counts.get(key) || 0) + 1) })
  return [...counts.entries()].sort((a, b) => b[1] - a[1] || labelSubcategory(a[0]).localeCompare(labelSubcategory(b[0])))
}

export function distanceMiles(a: GeoPoint, b: GeoPoint): number {
  const radius = 3958.7613, toRad = (degrees: number) => degrees * Math.PI / 180
  const dLat = toRad(b.latitude - a.latitude), dLon = toRad(b.longitude - a.longitude), lat1 = toRad(a.latitude), lat2 = toRad(b.latitude)
  const hav = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2
  return 2 * radius * Math.asin(Math.sqrt(hav))
}
export function distanceFrom(business: DirectoryBusiness, point: GeoPoint | null | undefined): number | null {
  if (!point || business.latitude == null || business.longitude == null) return null
  return distanceMiles(point, { latitude: business.latitude, longitude: business.longitude })
}

/** Trust, identity and usefulness dominate; rating and proximity are each capped at 5%. Featured placement contributes zero. */
export function directoryTrustScore(business: DirectoryBusiness, near?: GeoPoint | null): number {
  let score = 0
  if (business.owner_verified) score += 30
  if (/verified|confirmed|approved/i.test(business.ownership_status)) score += 15
  if (business.source_type && business.source_id) score += 10
  if (business.website_url) score += 7
  if (business.phone) score += 5
  if (business.business_email) score += 3
  if (business.short_description) score += 5
  if (business.specialties.length || business.tags.length) score += 5
  if (business.image_url) score += 5
  score += Math.min(5, Math.max(0, Number(business.rating || 0)))
  if (near) { const miles = distanceFrom(business, near); if (miles != null) score += Math.max(0, 5 - Math.min(5, miles / 10)) }
  return Number(score.toFixed(2))
}

export function filterDirectory(businesses: readonly DirectoryBusiness[], { category, subcategory = 'all', query, location = '', sort = 'recommended', near = null, maxDistanceMiles = 50 }: DirectoryFilter): DirectoryBusiness[] {
  const needle = query.trim().toLowerCase(), locationNeedle = location.trim().toLowerCase()
  const results = businesses.filter(business => {
    const categoryMatch = category === 'all' || business.category === category
    const subcategoryMatch = subcategory === 'all' || taxonomyKey(business.subcategory) === subcategory
    const searchMatch = !needle || [business.business_name,labelCategory(business.category),business.subcategory ? labelSubcategory(business.subcategory) : '',business.short_description,...business.specialties,...business.tags].filter(Boolean).join(' ').toLowerCase().includes(needle)
    const locationMatch = !locationNeedle || [business.neighborhood,business.city,business.state,business.address,business.postal_code,business.service_area].filter(Boolean).join(' ').toLowerCase().includes(locationNeedle)
    const nearDistance = distanceFrom(business, near), nearMatch = !near || (nearDistance != null && nearDistance <= maxDistanceMiles)
    return categoryMatch && subcategoryMatch && searchMatch && locationMatch && nearMatch
  })
  return [...results].sort((a, b) => {
    if (sort === 'distance' && near) return (distanceFrom(a, near) ?? Number.POSITIVE_INFINITY) - (distanceFrom(b, near) ?? Number.POSITIVE_INFINITY)
    if (sort === 'az') return a.business_name.localeCompare(b.business_name)
    const trustDelta = directoryTrustScore(b, near) - directoryTrustScore(a, near)
    return trustDelta || a.business_name.localeCompare(b.business_name)
  })
}

export function buildLocationGroups(businesses: readonly DirectoryBusiness[]): LocationGroup[] {
  const groups = new Map<string, { city: string; state: string; count: number; neighborhoods: Set<string>; postalCodes: Set<string> }>()
  businesses.forEach(business => {
    const city = business.city.trim(), state = business.state.trim(); if (!city) return
    const key = `${city.toLowerCase()}|${state.toLowerCase()}`, group = groups.get(key) ?? { city, state, count: 0, neighborhoods: new Set<string>(), postalCodes: new Set<string>() }
    group.count += 1; if (business.neighborhood) group.neighborhoods.add(business.neighborhood); if (business.postal_code) group.postalCodes.add(business.postal_code); groups.set(key, group)
  })
  return [...groups.entries()].map(([key, group]) => ({ key, city: group.city, state: group.state, count: group.count, neighborhoods: [...group.neighborhoods].sort(), postalCodes: [...group.postalCodes].sort() })).sort((a, b) => b.count - a.count || a.city.localeCompare(b.city))
}
export function featuredBusinesses(businesses: readonly DirectoryBusiness[]): DirectoryBusiness[] {
  return [...businesses].filter(business => business.featured || business.owner_verified || directoryTrustScore(business) >= 45).sort((a, b) => directoryTrustScore(b) - directoryTrustScore(a) || a.business_name.localeCompare(b.business_name)).slice(0, 8)
}
export function mapReadyBusinesses(businesses: readonly DirectoryBusiness[]) { return businesses.filter(business => business.latitude != null && business.longitude != null) }
export function singleCity(businesses: readonly DirectoryBusiness[]): string | null { const cities = new Set(businesses.map(business => business.city.trim()).filter(Boolean)); return cities.size === 1 ? [...cities][0] : null }
export function distinctImageCount(businesses: readonly DirectoryBusiness[]): number { return new Set(businesses.map(business => business.image_url).filter((url): url is string => Boolean(url))).size }

export type DirectoryResult = { businesses: DirectoryBusiness[]; error: string | null }
export async function fetchDirectory(client: TypedSupabaseClient): Promise<DirectoryResult> {
  const { data, error } = await client.from('black_pages_directory_v2').select('*').order('business_name')
  if (error) return { businesses: [], error: 'The live business directory could not be loaded.' }
  return { businesses: normalizeDirectoryRows(data).filter(isBusinessListing), error: null }
}

// Preserve unrelated account workflows while directory ranking changes independently.
export async function fetchSavedDirectoryIds(client: TypedSupabaseClient, userAuthId: string): Promise<string[]> {
  const { data } = await client.from('black_pages_favorites').select('directory_id').eq('user_auth_id', userAuthId)
  return (data ?? []).map(item => item.directory_id)
}
export async function addFavorite(client: TypedSupabaseClient, userAuthId: string, directoryId: string): Promise<{ error: boolean }> {
  const { error } = await client.from('black_pages_favorites').insert({ user_auth_id: userAuthId, directory_id: directoryId })
  return { error: Boolean(error) }
}
export async function removeFavorite(client: TypedSupabaseClient, userAuthId: string, directoryId: string): Promise<{ error: boolean }> {
  const { error } = await client.from('black_pages_favorites').delete().eq('user_auth_id', userAuthId).eq('directory_id', directoryId)
  return { error: Boolean(error) }
}
export type ClaimSubmission = { directoryId: string; claimantAuthId: string; claimantName: string; claimantEmail: string; roleAtBusiness: string }
export async function submitOwnerClaim(client: TypedSupabaseClient, claim: ClaimSubmission): Promise<{ error: string | null }> {
  const { error } = await client.from('black_pages_claims').upsert({ directory_id: claim.directoryId, claimant_auth_id: claim.claimantAuthId, claimant_name: claim.claimantName, claimant_email: claim.claimantEmail, role_at_business: claim.roleAtBusiness }, { onConflict: 'directory_id,claimant_auth_id' })
  return { error: error ? error.message : null }
}
