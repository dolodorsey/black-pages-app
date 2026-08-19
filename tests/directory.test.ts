import assert from 'node:assert/strict'
import test from 'node:test'
import type { DirectoryRow } from '../src/lib/database.types.ts'
import {
  countByCategory, directoryTrustScore, distinctImageCount, featuredBusinesses, filterDirectory, isBusinessListing,
  mapReadyBusinesses, normalizeDirectoryRow, normalizeDirectoryRows, singleCity,
} from '../src/services/directory.ts'

const baseRow: DirectoryRow = {
  directory_id: 'venue:1', source_type: 'venue', source_id: '1', business_name: 'Sweet Auburn Kitchen', slug: 'sweet-auburn-kitchen',
  category: 'food-beverage', subcategory: 'soul food', city: 'Atlanta', state: 'GA', neighborhood: 'Old Fourth Ward',
  address: '123 Auburn Ave, Atlanta, GA 30303', postal_code: '30303', short_description: 'Soul food staple.',
  website_url: 'https://example.com', instagram_handle: '@sweetauburn', phone: '404-555-0100', business_email: 'hello@example.com',
  image_url: 'https://example.com/hero.jpg', latitude: 33.755, longitude: -84.372, rating: 4.8, review_count: 210, price_range: '$$',
  featured: true, ownership_status: 'enterprise_sourced', owner_verified: false, tags: ['brunch', 'live music'], hours: { summary: 'Daily 9–5' },
  service_area: null, specialties: ['Catering'], facebook_url: null, linkedin_url: null, tiktok_url: null,
  serves_customers_at_location: true, service_radius_miles: null,
}

function makeRow(overrides: Partial<DirectoryRow> = {}): DirectoryRow { return { ...baseRow, ...overrides } }
function biz(overrides: Partial<DirectoryRow> = {}) { return normalizeDirectoryRow(makeRow(overrides)) }

test('normalizeDirectoryRow preserves location and directory profile fields', () => {
  const business = normalizeDirectoryRow(baseRow)
  assert.equal(business.postal_code, '30303')
  assert.equal(business.business_email, 'hello@example.com')
  assert.deepEqual(business.specialties, ['Catering'])
})

test('normalizeDirectoryRow substitutes safe values for nullable fields', () => {
  const business = normalizeDirectoryRow(makeRow({ state: null, tags: null, specialties: null }))
  assert.equal(business.state, '')
  assert.deepEqual(business.tags, [])
  assert.deepEqual(business.specialties, [])
})

test('normalizeDirectoryRows tolerates a null payload', () => {
  assert.deepEqual(normalizeDirectoryRows(null), [])
  assert.deepEqual(normalizeDirectoryRows(undefined), [])
})

const directory = normalizeDirectoryRows([
  baseRow,
  makeRow({ directory_id: 'venue:2', business_name: 'Westside Beauty Bar', category: 'beauty-wellness', subcategory: 'natural_salon', neighborhood: 'West End', address: '742 Ralph David Abernathy Blvd, Atlanta, GA 30310', postal_code: '30310', short_description: 'Braids and locs.', rating: 4.6, featured: false, tags: ['locs'], specialties: ['Natural hair'] }),
  makeRow({ directory_id: 'listing:3', source_type: 'listing', business_name: 'Peachtree Tech Repair', category: 'technology', subcategory: 'computer-repair', city: 'Decatur', state: 'GA', neighborhood: null, address: null, postal_code: '30030', short_description: 'Phone and laptop repair.', latitude: null, longitude: null, rating: null, featured: false, tags: ['technology', 'repair'], specialties: ['Laptop repair'] }),
])

test('event programming is rejected while actual venue businesses remain valid', () => {
  assert.equal(isBusinessListing(biz({ subcategory: 'event_series' })), false)
  assert.equal(isBusinessListing(biz({ category: 'venues-spaces', subcategory: 'event-venues' })), true)
})

test('countByCategory counts canonical business categories', () => {
  const counts = countByCategory([...directory, directory[1]])
  assert.deepEqual(counts, [['beauty-wellness', 2], ['food-beverage', 1], ['technology', 1]])
})

test('WHAT search covers name, description, category labels, specialties and tags', () => {
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: 'repair' }).map(item => item.directory_id), ['listing:3'])
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: 'Natural hair' }).map(item => item.directory_id), ['venue:2'])
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: 'Food & Beverage' }).map(item => item.directory_id), ['venue:1'])
})

test('WHERE search covers neighborhood, city, state, address and ZIP', () => {
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: '', location: 'West End' }).map(item => item.directory_id), ['venue:2'])
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: '', location: '30030' }).map(item => item.directory_id), ['listing:3'])
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: '', location: 'Auburn Ave' }).map(item => item.directory_id), ['venue:1'])
})

test('A-Z sorting is alphabetical while recommended uses trust intelligence, not featured placement', () => {
  assert.deepEqual(filterDirectory(directory, { category: 'all', query: '', sort: 'az' }).map(item => item.business_name), ['Peachtree Tech Repair', 'Sweet Auburn Kitchen', 'Westside Beauty Bar'])
  const recommended=filterDirectory(directory, { category: 'all', query: '', sort: 'recommended' })
  assert.ok(directoryTrustScore(recommended[0]) >= directoryTrustScore(recommended[1]))
  assert.equal(directoryTrustScore(biz({ featured:false })),directoryTrustScore(biz({ featured:true })))
})

test('mapReadyBusinesses keeps only businesses with coordinates', () => {
  assert.deepEqual(mapReadyBusinesses(directory).map(item => item.directory_id), ['venue:1', 'venue:2'])
})

test('featuredBusinesses only returns profiles that meet a real trust threshold or explicit merchandising inclusion', () => {
  const featured=featuredBusinesses(directory)
  assert.ok(featured.some(item=>item.directory_id==='venue:1'))
  assert.ok(featured.every((item)=>item.featured||item.owner_verified||directoryTrustScore(item)>=45))
})

test('singleCity detects shared city', () => {
  assert.equal(singleCity([biz({ city: 'Atlanta' }), biz({ city: 'Atlanta' })]), 'Atlanta')
  assert.equal(singleCity([biz({ city: 'Atlanta' }), biz({ city: 'Phoenix' })]), null)
})

test('distinctImageCount counts unique image URLs', () => {
  const shared = 'https://images.example.com/a.jpg'
  assert.equal(distinctImageCount([biz({ image_url: shared }), biz({ image_url: shared }), biz({ image_url: 'https://example.com/b.png' })]), 2)
})