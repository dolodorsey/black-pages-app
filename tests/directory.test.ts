import assert from 'node:assert/strict'
import test from 'node:test'
import type { DirectoryRow } from '../src/lib/database.types.ts'
import {
  countByCategory,
  distinctImageCount,
  featuredBusinesses,
  filterDirectory,
  isBusinessListing,
  mapReadyBusinesses,
  normalizeDirectoryRow,
  normalizeDirectoryRows,
  singleCity,
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

function biz(overrides: Partial<DirectoryRow> = {}) {
  return normalizeDirectoryRow(makeRow(overrides))
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
  const business = normalizeDirectoryRow(makeRow({ tags: ['brunch', '', null as unknown as string, 'patio'] }))
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
    subcategory: 'natural_salon',
    neighborhood: 'West End',
    address: '900 Ralph David Abernathy Blvd SW',
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
    city: 'Decatur',
    state: 'GA',
    neighborhood: null,
    address: null,
    short_description: 'Phone and laptop repair.',
    latitude: null,
    longitude: null,
    rating: null,
    featured: false,
    tags: ['technology', 'repair'],
  }),
])

test('event-only records are rejected while event venues remain valid businesses', () => {
  assert.equal(isBusinessListing(biz({ category: 'day_party', subcategory: 'day_party' })), false)
  assert.equal(isBusinessListing(biz({ category: 'special_events', subcategory: 'festival' })), false)
  assert.equal(isBusinessListing(biz({ category: 'nightlife', subcategory: 'event_series' })), false)
  assert.equal(isBusinessListing(biz({ category: 'event_venue', subcategory: 'Event Venues' })), true)
})

test('countByCategory counts business categories and sorts ties by label', () => {
  const counts = countByCategory([...directory, directory[1]])
  assert.deepEqual(counts, [['beauty', 2], ['business', 1], ['restaurant', 1]])
})

test('filterDirectory returns everything for the default filter', () => {
  assert.equal(filterDirectory(directory, { category: 'all', query: '' }).length, 3)
})

test('filterDirectory narrows by category', () => {
  const results = filterDirectory(directory, { category: 'beauty', query: '' })
  assert.deepEqual(results.map(item => item.business_name), ['Westside Beauty Bar'])
})

test('WHAT search covers name, service description, category and tags', () => {
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: 'repair' }).map(item => item.directory_id), ['listing:3'])
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: 'locs' }).map(item => item.directory_id), ['venue:2'])
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: 'Restaurants' }).map(item => item.directory_id), ['venue:1'])
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: 'no such business' }), [])
})

test('WHERE search covers neighborhood, city, state and address separately from WHAT', () => {
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: '', location: 'West End' }).map(item => item.directory_id), ['venue:2'])
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: '', location: 'Decatur' }).map(item => item.directory_id), ['listing:3'])
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: '', location: 'Auburn Ave' }).map(item => item.directory_id), ['venue:1'])
})

test('WHAT and WHERE can be combined', () => {
  assert.deepEqual(
    filterDirectory(directory, { category: 'all', query: 'repair', location: 'Decatur' }).map(item => item.directory_id),
    ['listing:3'],
  )
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: 'repair', location: 'Atlanta' }), [])
})

test('A-Z sorting is alphabetical while recommended keeps featured and rating priority', () => {
  assert.deepEqual(
    filterDirectory(directory, { category: 'all', query: '', sort: 'az' }).map(item => item.business_name),
    ['Peachtree Tech Repair', 'Sweet Auburn Kitchen', 'Westside Beauty Bar'],
  )
  assert.deepEqual(
    filterDirectory(directory, { category: 'all', query: '', sort: 'recommended' }).map(item => item.business_name),
    ['Sweet Auburn Kitchen', 'Westside Beauty Bar', 'Peachtree Tech Repair'],
  )
})

test('mapReadyBusinesses keeps only rows with both coordinates', () => {
  assert.deepEqual(mapReadyBusinesses(directory).map(item => item.directory_id), ['venue:1', 'venue:2'])
})

test('featuredBusinesses prioritizes featured and highly rated business profiles', () => {
  assert.deepEqual(featuredBusinesses(directory).map(item => item.directory_id), ['venue:1', 'venue:2'])
})

test('singleCity returns the city when every listing shares it', () => {
  assert.equal(singleCity([biz({ city: 'Atlanta' }), biz({ city: 'Atlanta' })]), 'Atlanta')
})

test('singleCity returns null when the set spans more than one city', () => {
  assert.equal(singleCity([biz({ city: 'Atlanta' }), biz({ city: 'Phoenix' })]), null)
})

test('distinctImageCount counts distinct urls, not listings with an image', () => {
  const shared = 'https://images.unsplash.com/photo-1517991104123'
  assert.equal(
    distinctImageCount([
      biz({ image_url: shared }),
      biz({ image_url: shared }),
      biz({ image_url: 'https://example.com/b.png' }),
    ]),
    2,
  )
})
