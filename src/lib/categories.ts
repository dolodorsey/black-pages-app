/** Category vocabulary shared by the directory UI and the application form. */

export const categoryLabels: Record<string, string> = {
  restaurant: 'Restaurants',
  nightclub: 'Nightclubs',
  brunch: 'Breakfast & Brunch',
  lounge: 'Lounges',
  hookah: 'Hookah Lounges',
  coffee: 'Coffee & Tea',
  culture: 'Arts & Culture',
  nightlife: 'Nightlife Businesses',
  beauty: 'Beauty',
  shopping: 'Shopping & Retail',
  fitness: 'Fitness',
  food_truck: 'Food Trucks',
  bar: 'Bars',
  comedy: 'Comedy Clubs',
  jazz: 'Jazz Clubs',
  spa: 'Spas',
  wellness: 'Wellness',
  event_venue: 'Event Venues',
  sports_bar: 'Sports Bars',
  business: 'Professional Services',
  technology: 'Technology',
  automotive: 'Automotive',
  health: 'Health',
  education: 'Education',
  home_services: 'Home Services',
}

/** Categories offered on the "list a business" application form. */
export const listingCategories = [
  'Food & Beverage',
  'Beauty & Wellness',
  'Professional Services',
  'Retail',
  'Arts & Culture',
  'Home Services',
  'Technology',
  'Automotive',
  'Health',
  'Education',
]

/**
 * Stable comparison key for taxonomy values coming from multiple directory
 * sources. It intentionally collapses casing, spaces, punctuation and
 * underscores so values such as `soul_food`, `Soul Food`, and `soul-food`
 * behave as one subcategory in navigation and filtering.
 */
export function taxonomyKey(value: string | null | undefined): string {
  return (value || '')
    .trim()
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[’']/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
}

export function labelCategory(value: string) {
  return categoryLabels[value] || value.replaceAll('_', ' ').replace(/\b\w/g, character => character.toUpperCase())
}

export function labelSubcategory(value: string) {
  return value
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, character => character.toUpperCase())
}

/**
 * Pluralise a count without lying about it. "1 businesses" reads as broken
 * data; during a directory outage the count can legitimately be 1 or 0.
 */
export function pluralize(count: number, singular: string, plural = `${singular}s`): string {
  return `${count} ${count === 1 ? singular : plural}`
}
