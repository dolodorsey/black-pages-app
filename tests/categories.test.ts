import assert from 'node:assert/strict'
import test from 'node:test'
import { taxonomyKey } from '../src/lib/categories.ts'
import { countBySubcategory, filterDirectory, type DirectoryBusiness } from '../src/services/directory.ts'

function business(overrides: Partial<DirectoryBusiness> = {}): DirectoryBusiness {
  return {
    directory_id: 'venue:1',
    source_type: 'venue',
    source_id: '1',
    business_name: 'Sample Business',
    slug: 'sample-business',
    category: 'restaurant',
    subcategory: 'soul_food',
    city: 'Atlanta',
    state: 'GA',
    neighborhood: null,
    address: null,
    short_description: null,
    website_url: null,
    instagram_handle: null,
    phone: null,
    image_url: null,
    latitude: null,
    longitude: null,
    rating: null,
    review_count: null,
    price_range: null,
    featured: false,
    ownership_status: 'enterprise_sourced',
    owner_verified: false,
    tags: [],
    ...overrides,
  }
}

test('taxonomyKey collapses source spelling and punctuation variants', () => {
  assert.equal(taxonomyKey('Soul Food'), 'soul_food')
  assert.equal(taxonomyKey('soul-food'), 'soul_food')
  assert.equal(taxonomyKey('soul_food'), 'soul_food')
})

test('countBySubcategory combines duplicate taxonomy variants', () => {
  const businesses = [
    business({ directory_id: '1', subcategory: 'soul_food' }),
    business({ directory_id: '2', subcategory: 'Soul Food' }),
    business({ directory_id: '3', subcategory: 'vegan' }),
  ]
  assert.deepEqual(countBySubcategory(businesses, 'restaurant'), [['soul_food', 2], ['vegan', 1]])
})

test('filterDirectory supports category and normalized subcategory together', () => {
  const businesses = [
    business({ directory_id: '1', subcategory: 'Soul Food' }),
    business({ directory_id: '2', subcategory: 'vegan' }),
    business({ directory_id: '3', category: 'beauty', subcategory: 'salon' }),
  ]
  assert.deepEqual(
    filterDirectory(businesses, { category: 'restaurant', subcategory: 'soul_food', query: '' }).map(item => item.directory_id),
    ['1'],
  )
})
