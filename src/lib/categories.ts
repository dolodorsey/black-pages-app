/** Canonical business-directory labels used while the live taxonomy loads. */
export const categoryLabels: Record<string, string> = {
  'agriculture-farming': 'Agriculture & Farming',
  'arts-culture': 'Arts & Culture',
  automotive: 'Automotive',
  'beauty-wellness': 'Beauty & Grooming',
  'business-services': 'Business Services',
  'childcare-family': 'Childcare & Family',
  'cleaning-maintenance': 'Cleaning & Maintenance',
  'construction-trades': 'Construction & Trades',
  'creative-media': 'Creative & Media',
  education: 'Education',
  'fashion-apparel': 'Fashion & Apparel',
  'financial-services': 'Financial Services',
  'food-beverage': 'Food & Beverage',
  health: 'Health & Medical',
  'home-services': 'Home & Garden',
  'hospitality-travel': 'Hospitality & Travel',
  'legal-services': 'Legal Services',
  'logistics-transportation': 'Logistics & Transportation',
  'manufacturing-industrial': 'Manufacturing & Industrial',
  'marketing-advertising': 'Marketing & Advertising',
  'nightlife-entertainment': 'Nightlife & Entertainment Businesses',
  community: 'Nonprofit & Community',
  'personal-services': 'Personal Services',
  'pet-services': 'Pet Services',
  'professional-services': 'Professional Services',
  'real-estate': 'Real Estate',
  retail: 'Retail & Shopping',
  'security-safety': 'Security & Safety',
  'sports-fitness': 'Sports & Fitness',
  technology: 'Technology',
  'wholesale-distribution': 'Wholesale & Distribution',
  'venues-spaces': 'Venues & Spaces',
}

/** Stable slug for taxonomy values arriving with spaces, punctuation, hyphens or underscores. */
export function taxonomyKey(value: string | null | undefined): string {
  return (value || '')
    .trim()
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[’']/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

export function labelCategory(value: string) {
  return categoryLabels[value] || value.replaceAll('_', ' ').replaceAll('-', ' ').replace(/\b\w/g, character => character.toUpperCase())
}

export function labelSubcategory(value: string) {
  return value
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, character => character.toUpperCase())
}

export function pluralize(count: number, singular: string, plural = `${singular}s`): string {
  return `${count} ${count === 1 ? singular : plural}`
}
