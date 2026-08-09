import assert from 'node:assert/strict'
import test from 'node:test'
import type { DirectoryRow } from '../src/lib/database.types.ts'
import {
  countByCategory,
  featuredBusinesses,
  filterDirectory,
  mapReadyBusinesses,
  normalizeDirectoryRow,
  normalizeDirectoryRows,
} from '../src/services/directory.ts'

const baseRow: DirectoryRow = {
  directory_id: 'venue:1',
  source_type: 'venue',
  source_id: '1',
  business_name: 'Sweet Auburn Kitchen',
  slug: 'sweet-auburn-kitchen',
  category: 'restaurant',
  subcategory: 'soul food',
  city: 'Atlanta',
  state: 'GA',
  neighborhood: 'Old Fourth Ward',
  address: '123 Auburn Ave',
  short_description: 'Soul food staple.',
  website_url: 'https://example.com',
  instagram_handle: '@sweetauburn',
  phone: '404-555-0100',
  image_url: 'https://example.com/hero.jpg',
  latitude: 33.755,
  longitude: -84.372,
  rating: 4.8,
  review_count: 210,
  price_range: '$$',
  featured: true,
  ownership_status: 'enterprise_sourced',
  owner_verified: false,
  tags: ['brunch', 'live music'],
}

function makeRow(overrides: Partial<DirectoryRow> = {}): DirectoryRow {
  return { ...baseRow, ...overrides }
}

test('normalizeDirectoryRow passes a complete row through unchanged', () => {
  assert.deepEqual(normalizeDirectoryRow(baseRow), { ...baseRow, tags: ['brunch', 'live music'] })
})

test('normalizeDirectoryRow substitutes safe values for nullable view columns', () => {
  const business = normalizeDirectoryRow(makeRow({ state: null, tags: null }))
  assert.equal(business.state, '')
  assert.deepEqual(business.tags, [])
})

test('normalizeDirectoryRow drops empty and non-string tags', () => {
  const business = normalizeDirectoryRow(
    makeRow({ tags: ['brunch', '', null as unknown as string, 'patio'] }),
  )
  assert.deepEqual(business.tags, ['brunch', 'patio'])
})

test('normalizeDirectoryRow coerces numeric columns and keeps nulls null', () => {
  const coerced = normalizeDirectoryRow(makeRow({ rating: '4.7' as unknown as number }))
  assert.equal(coerced.rating, 4.7)
  const missing = normalizeDirectoryRow(makeRow({ rating: null, latitude: null, longitude: null, review_count: null }))
  assert.equal(missing.rating, null)
  assert.equal(missing.latitude, null)
  assert.equal(missing.longitude, null)
  assert.equal(missing.review_count, null)
})

test('normalizeDirectoryRow treats non-boolean flags as false', () => {
  const business = normalizeDirectoryRow(makeRow({ featured: null as unknown as boolean, owner_verified: true }))
  assert.equal(business.featured, false)
  assert.equal(business.owner_verified, true)
})

test('normalizeDirectoryRows tolerates a null payload', () => {
  assert.deepEqual(normalizeDirectoryRows(null), [])
  assert.deepEqual(normalizeDirectoryRows(undefined), [])
  assert.equal(normalizeDirectoryRows([baseRow]).length, 1)
})

const directory = normalizeDirectoryRows([
  baseRow,
  makeRow({
    directory_id: 'venue:2',
    business_name: 'Westside Beauty Bar',
    category: 'beauty',
    neighborhood: 'West End',
    short_description: 'Braids and locs.',
    rating: 4.6,
    featured: false,
    tags: ['locs'],
  }),
  makeRow({
    directory_id: 'listing:3',
    source_type: 'listing',
    business_name: 'Peachtree Tech Repair',
    category: 'business',
    subcategory: null,
    neighborhood: null,
    short_description: null,
    latitude: null,
    longitude: null,
    rating: null,
    featured: false,
    tags: null,
  }),
])

test('countByCategory counts each category, most populated first', () => {
  const counts = countByCategory([...directory, directory[1]])
  assert.deepEqual(counts, [['beauty', 2], ['restaurant', 1], ['business', 1]])
})

test('filterDirectory returns everything for the default filter', () => {
  assert.equal(filterDirectory(directory, { category: 'all', query: '' }).length, 3)
})

test('filterDirectory narrows by category', () => {
  const results = filterDirectory(directory, { category: 'beauty', query: '' })
  assert.deepEqual(results.map(item => item.business_name), ['Westside Beauty Bar'])
})

test('filterDirectory searches name, neighborhood, description and tags case-insensitively', () => {
  assert.deepEqual(
    filterDirectory(directory, { category: 'all', query: '  WEST end ' }).map(item => item.directory_id),
    ['venue:2'],
  )
  assert.deepEqual(
    filterDirectory(directory, { category: 'all', query: 'live music' }).map(item => item.directory_id),
    ['venue:1'],
  )
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: 'no such business' }), [])
})

test('filterDirectory tolerates rows with null text columns', () => {
  assert.deepEqual(
    filterDirectory(directory, { category: 'all', query: 'peachtree' }).map(item => item.directory_id),
    ['listing:3'],
  )
})

test('mapReadyBusinesses keeps only rows with both coordinates', () => {
  assert.deepEqual(mapReadyBusinesses(directory).map(item => item.directory_id), ['venue:1', 'venue:2'])
})

test('featuredBusinesses includes flagged and highly rated rows only', () => {
  assert.deepEqual(featuredBusinesses(directory).map(item => item.directory_id), ['venue:1', 'venue:2'])
})
