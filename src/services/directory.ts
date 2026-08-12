/**
 * Typed data access for THE BLACK PAGES business directory.
 *
 * THE BLACK PAGES is a business directory, not an events feed. Event-only
 * source rows are deliberately excluded before they reach navigation, counts,
 * search, saved lists, or the public directory UI.
 */
import type { SupabaseClient } from '@supabase/supabase-js'
import { labelCategory, labelSubcategory, taxonomyKey } from '../lib/categories.ts'
import type { Database, DirectoryRow } from '../lib/database.types.ts'

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
  short_description: string | null
  website_url: string | null
  instagram_handle: string | null
  phone: string | null
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
}

export type CategoryCount = readonly [category: string, count: number]
export type SubcategoryCount = readonly [subcategory: string, count: number]
export type DirectorySort = 'recommended' | 'az'

export type DirectoryFilter = {
  category: string
  subcategory?: string
  query: string
  location?: string
  sort?: DirectorySort
}

const EVENT_ONLY_CATEGORIES = new Set(['day_party', 'special_events'])
const EVENT_ONLY_SUBCATEGORIES = new Set(['event_series'])

function toNullableNumber(value: number | string | null | undefined): number | null {
  if (value === null || value === undefined || value === '') return null
  const parsed = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function toText(value: string | null | undefined): string {
  return typeof value === 'string' ? value : ''
}

export function normalizeDirectoryRow(row: DirectoryRow): DirectoryBusiness {
  return {
    directory_id: toText(row.directory_id),
    source_type: toText(row.source_type),
    source_id: toText(row.source_id),
    business_name: toText(row.business_name),
    slug: toText(row.slug),
    category: toText(row.category),
    subcategory: row.subcategory ?? null,
    city: toText(row.city),
    state: toText(row.state),
    neighborhood: row.neighborhood ?? null,
    address: row.address ?? null,
    short_description: row.short_description ?? null,
    website_url: row.website_url ?? null,
    instagram_handle: row.instagram_handle ?? null,
    phone: row.phone ?? null,
    image_url: row.image_url ?? null,
    latitude: toNullableNumber(row.latitude),
    longitude: toNullableNumber(row.longitude),
    rating: toNullableNumber(row.rating),
    review_count: toNullableNumber(row.review_count),
    price_range: row.price_range ?? null,
    featured: row.featured === true,
    ownership_status: toText(row.ownership_status),
    owner_verified: row.owner_verified === true,
    tags: Array.isArray(row.tags) ? row.tags.filter(tag => typeof tag === 'string' && tag.length > 0) : [],
  }
}

export function normalizeDirectoryRows(rows: DirectoryRow[] | null | undefined): DirectoryBusiness[] {
  return (rows ?? []).map(normalizeDirectoryRow)
}

/** True only for records that represent businesses rather than event programming. */
export function isBusinessListing(business: DirectoryBusiness): boolean {
  if (EVENT_ONLY_CATEGORIES.has(taxonomyKey(business.category))) return false
  if (EVENT_ONLY_SUBCATEGORIES.has(taxonomyKey(business.subcategory))) return false
  return true
}

export function countByCategory(businesses: readonly DirectoryBusiness[]): CategoryCount[] {
  const counts = new Map<string, number>()
  businesses.forEach(business => counts.set(business.category, (counts.get(business.category) || 0) + 1))
  return [...counts.entries()].sort((a, b) => b[1] - a[1] || labelCategory(a[0]).localeCompare(labelCategory(b[0])))
}

export function countBySubcategory(
  businesses: readonly DirectoryBusiness[],
  category = 'all',
): SubcategoryCount[] {
  const counts = new Map<string, number>()
  businesses.forEach(business => {
    if (category !== 'all' && business.category !== category) return
    const key = taxonomyKey(business.subcategory)
    if (!key) return
    counts.set(key, (counts.get(key) || 0) + 1)
  })
  return [...counts.entries()].sort((a, b) => b[1] - a[1] || labelSubcategory(a[0]).localeCompare(labelSubcategory(b[0])))
}

/** Business-name/service + category + location search used by the directory. */
export function filterDirectory(
  businesses: readonly DirectoryBusiness[],
  { category, subcategory = 'all', query, location = '', sort = 'recommended' }: DirectoryFilter,
): DirectoryBusiness[] {
  const needle = query.trim().toLowerCase()
  const locationNeedle = location.trim().toLowerCase()

  const results = businesses.filter(business => {
    const categoryMatch = category === 'all' || business.category === category
    const subcategoryMatch = subcategory === 'all' || taxonomyKey(business.subcategory) === subcategory
    const searchMatch =
      !needle ||
      [
        business.business_name,
        labelCategory(business.category),
        business.subcategory ? labelSubcategory(business.subcategory) : '',
        business.short_description,
        ...business.tags,
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(needle)
    const locationMatch =
      !locationNeedle ||
      [business.neighborhood, business.city, business.state, business.address]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(locationNeedle)
    return categoryMatch && subcategoryMatch && searchMatch && locationMatch
  })

  return [...results].sort((a, b) => {
    if (sort === 'az') return a.business_name.localeCompare(b.business_name)
    if (a.featured !== b.featured) return a.featured ? -1 : 1
    const ratingDelta = Number(b.rating || 0) - Number(a.rating || 0)
    return ratingDelta || a.business_name.localeCompare(b.business_name)
  })
}

export function mapReadyBusinesses(businesses: readonly DirectoryBusiness[]): DirectoryBusiness[] {
  return businesses.filter(business => business.latitude != null && business.longitude != null)
}

/** Curated business rail: explicitly featured first, then strong directory profiles. */
export function featuredBusinesses(businesses: readonly DirectoryBusiness[]): DirectoryBusiness[] {
  return [...businesses]
    .filter(business => business.featured || Number(business.rating || 0) >= 4.5)
    .sort((a, b) => Number(b.featured) - Number(a.featured) || Number(b.rating || 0) - Number(a.rating || 0))
    .slice(0, 8)
}

export function singleCity(businesses: readonly DirectoryBusiness[]): string | null {
  const cities = new Set(
    businesses.map(business => (business.city || '').trim()).filter(city => city.length > 0),
  )
  return cities.size === 1 ? [...cities][0] : null
}

export function distinctImageCount(businesses: readonly DirectoryBusiness[]): number {
  return new Set(
    businesses.map(business => business.image_url).filter((url): url is string => Boolean(url)),
  ).size
}

export type DirectoryResult = {
  businesses: DirectoryBusiness[]
  error: string | null
}

/** Reads the published directory and strips event-only records before returning it. */
export async function fetchDirectory(client: TypedSupabaseClient): Promise<DirectoryResult> {
  const { data, error } = await client
    .from('black_pages_directory')
    .select('*')
    .order('featured', { ascending: false })
    .order('rating', { ascending: false, nullsFirst: false })
    .order('business_name')

  if (error) return { businesses: [], error: 'The live business directory could not be loaded.' }
  return { businesses: normalizeDirectoryRows(data).filter(isBusinessListing), error: null }
}

export async function fetchSavedDirectoryIds(client: TypedSupabaseClient, userAuthId: string): Promise<string[]> {
  const { data } = await client.from('black_pages_favorites').select('directory_id').eq('user_auth_id', userAuthId)
  return (data ?? []).map(item => item.directory_id)
}

export async function addFavorite(
  client: TypedSupabaseClient,
  userAuthId: string,
  directoryId: string,
): Promise<{ error: boolean }> {
  const { error } = await client
    .from('black_pages_favorites')
    .insert({ user_auth_id: userAuthId, directory_id: directoryId })
  return { error: Boolean(error) }
}

export async function removeFavorite(
  client: TypedSupabaseClient,
  userAuthId: string,
  directoryId: string,
): Promise<{ error: boolean }> {
  const { error } = await client
    .from('black_pages_favorites')
    .delete()
    .eq('user_auth_id', userAuthId)
    .eq('directory_id', directoryId)
  return { error: Boolean(error) }
}

export type ClaimSubmission = {
  directoryId: string
  claimantAuthId: string
  claimantName: string
  claimantEmail: string
  roleAtBusiness: string
}

export async function submitOwnerClaim(
  client: TypedSupabaseClient,
  claim: ClaimSubmission,
): Promise<{ error: string | null }> {
  const { error } = await client.from('black_pages_claims').upsert(
    {
      directory_id: claim.directoryId,
      claimant_auth_id: claim.claimantAuthId,
      claimant_name: claim.claimantName,
      claimant_email: claim.claimantEmail,
      role_at_business: claim.roleAtBusiness,
    },
    { onConflict: 'directory_id,claimant_auth_id' },
  )
  return { error: error ? error.message : null }
}
