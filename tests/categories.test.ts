import assert from 'node:assert/strict'
import test from 'node:test'
import { taxonomyKey } from '../src/lib/categories.ts'
import { buildLocationGroups, countBySubcategory, distanceMiles, filterDirectory, type DirectoryBusiness } from '../src/services/directory.ts'

function business(overrides: Partial<DirectoryBusiness> = {}): DirectoryBusiness {
  return {
    directory_id: 'venue:1', source_type: 'venue', source_id: '1', business_name: 'Sample Business', slug: 'sample-business',
    category: 'food-beverage', subcategory: 'soul_food', city: 'Atlanta', state: 'GA', neighborhood: 'Downtown',
    address: '100 Peachtree St, Atlanta, GA 30303', postal_code: '30303', short_description: null, website_url: null,
    instagram_handle: null, phone: null, business_email: null, image_url: null, latitude: 33.75, longitude: -84.39,
    rating: null, review_count: null, price_range: null, featured: false, ownership_status: 'enterprise_sourced', owner_verified: false,
    tags: [], hours: null, service_area: null, specialties: [], facebook_url: null, linkedin_url: null, tiktok_url: null,
    serves_customers_at_location: true, service_radius_miles: null, ...overrides,
  }
}

test('taxonomyKey collapses source spelling and punctuation variants to URL slugs', () => {
  assert.equal(taxonomyKey('Soul Food'), 'soul-food')
  assert.equal(taxonomyKey('soul-food'), 'soul-food')
  assert.equal(taxonomyKey('soul_food'), 'soul-food')
})

test('countBySubcategory combines duplicate source taxonomy variants', () => {
  const businesses = [business({ directory_id: '1', subcategory: 'soul_food' }), business({ directory_id: '2', subcategory: 'Soul Food' }), business({ directory_id: '3', subcategory: 'vegan' })]
  assert.deepEqual(countBySubcategory(businesses, 'food-beverage'), [['soul-food', 2], ['vegan', 1]])
})

test('filterDirectory supports category, normalized subcategory, ZIP and specialty search', () => {
  const businesses = [
    business({ directory_id: '1', subcategory: 'Soul Food', specialties: ['Catering'] }),
    business({ directory_id: '2', subcategory: 'vegan', postal_code: '30318' }),
    business({ directory_id: '3', category: 'beauty-wellness', subcategory: 'hair-salons' }),
  ]
  assert.deepEqual(filterDirectory(businesses, { category: 'food-beverage', subcategory: 'soul-food', query: 'catering' }).map(item => item.directory_id), ['1'])
  assert.deepEqual(filterDirectory(businesses, { category: 'all', query: '', location: '30318' }).map(item => item.directory_id), ['2'])
})

test('buildLocationGroups creates city pages with neighborhoods and ZIP codes', () => {
  const groups = buildLocationGroups([
    business({ directory_id: '1', neighborhood: 'Downtown', postal_code: '30303' }),
    business({ directory_id: '2', neighborhood: 'West End', postal_code: '30310' }),
  ])
  assert.equal(groups[0].city, 'Atlanta')
  assert.equal(groups[0].count, 2)
  assert.deepEqual(groups[0].postalCodes, ['30303', '30310'])
})

test('distanceMiles produces useful near-me distances', () => {
  const atlanta = { latitude: 33.749, longitude: -84.388 }
  const nearby = { latitude: 33.76, longitude: -84.38 }
  const distance = distanceMiles(atlanta, nearby)
  assert.ok(distance > 0 && distance < 5)
})
