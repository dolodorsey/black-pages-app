/** Category vocabulary shared by the directory UI and the application form. */

export const categoryLabels: Record<string, string> = {
  restaurant: 'Restaurants',
  nightclub: 'Nightlife',
  brunch: 'Brunch',
  lounge: 'Lounges',
  hookah: 'Hookah',
  coffee: 'Coffee',
  culture: 'Arts & Culture',
  nightlife: 'Nightlife',
  beauty: 'Beauty',
  shopping: 'Shopping',
  fitness: 'Fitness',
  food_truck: 'Food Trucks',
  bar: 'Bars',
  comedy: 'Comedy',
  jazz: 'Jazz',
  spa: 'Spa',
  wellness: 'Wellness',
  special_events: 'Events',
  day_party: 'Day Parties',
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

export function labelCategory(value: string) {
  return categoryLabels[value] || value.replaceAll('_', ' ').replace(/\b\w/g, character => character.toUpperCase())
}
