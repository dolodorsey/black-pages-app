/**
 * Typed data access for the BLACK PAGES directory.
 *
 * Everything below is either a pure function (normalisation, filtering,
 * counting) or a thin typed wrapper over a Supabase client passed in by the
 * caller. Keeping the client as a parameter means the pure parts are unit
 * testable under `node --test` without a browser or network.
 */
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database, DirectoryRow } from '../lib/database.types'

export type TypedSupabaseClient = SupabaseClient<Database>

/**
 * Directory row after normalisation. Fields the UI treats as optional stay
 * nullable so rendering is unchanged; fields the UI always renders are
 * guaranteed non-null here instead of at every call site.
 */
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

export type DirectoryFilter = {
  category: string
  query: string
}

/** Coerces PostgREST numerics (which may arrive as strings) to a finite number. */
function toNullableNumber(value: number | string | null | undefined): number | null {
  if (value === null || value === undefined || value === '') return null
  const parsed = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function toText(value: string | null | undefined): string {
  return typeof value === 'string' ? value : ''
}

/** Normalises one raw view row into the shape the UI consumes. */
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

/** Normalises a result set, tolerating a null payload. */
export function normalizeDirectoryRows(rows: DirectoryRow[] | null | undefined): DirectoryBusiness[] {
  return (rows ?? []).map(normalizeDirectoryRow)
}

/** Category counts, most populated first — drives the category rail. */
export function countByCategory(businesses: readonly DirectoryBusiness[]): CategoryCount[] {
  const counts = new Map<string, number>()
  businesses.forEach(business => counts.set(business.category, (counts.get(business.category) || 0) + 1))
  return [...counts.entries()].sort((a, b) => b[1] - a[1])
}

/** Category + free-text filter used by the discover screen. */
export function filterDirectory(
  businesses: readonly DirectoryBusiness[],
  { category, query }: DirectoryFilter,
): DirectoryBusiness[] {
  const needle = query.trim().toLowerCase()
  return businesses.filter(business => {
    const categoryMatch = category === 'all' || business.category === category
    const searchMatch =
      !needle ||
      [
        business.business_name,
        business.category,
        business.subcategory,
        business.neighborhood,
        business.city,
        business.short_description,
        ...business.tags,
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(needle)
    return categoryMatch && searchMatch
  })
}

/** Businesses that can be plotted, i.e. have both coordinates. */
export function mapReadyBusinesses(businesses: readonly DirectoryBusiness[]): DirectoryBusiness[] {
  return businesses.filter(business => business.latitude != null && business.longitude != null)
}

/** Featured rail: explicitly featured, or highly rated. */
export function featuredBusinesses(businesses: readonly DirectoryBusiness[]): DirectoryBusiness[] {
  return businesses.filter(business => business.featured || Number(business.rating || 0) >= 4.5).slice(0, 8)
}

export type DirectoryResult = {
  businesses: DirectoryBusiness[]
  /** Operator-facing message when the published count is unknown. */
  error: string | null
}

/** Reads every published directory row in the order the UI expects. */
export async function fetchDirectory(client: TypedSupabaseClient): Promise<DirectoryResult> {
  const { data, error } = await client
    .from('black_pages_directory')
    .select('*')
    .order('featured', { ascending: false })
    .order('rating', { ascending: false, nullsFirst: false })
    .order('business_name')

  if (error) return { businesses: [], error: 'The live directory could not be loaded.' }
  return { businesses: normalizeDirectoryRows(data), error: null }
}

/** Directory ids the signed-in user has saved. */
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

/** Submits (or updates) an owner claim. Approval stays service-role only. */
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
