import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../lib/database.types.ts'

export type TaxonomyCategory = {
  slug: string
  name: string
  description: string | null
  sort_order: number
}

export type TaxonomySubcategory = {
  category_slug: string
  slug: string
  name: string
  target_per_city: number
}

export type TaxonomyResult = {
  categories: TaxonomyCategory[]
  subcategories: TaxonomySubcategory[]
  error: string | null
}

export async function fetchTaxonomy(client: SupabaseClient<Database>): Promise<TaxonomyResult> {
  const [categoryResult, subcategoryResult] = await Promise.all([
    client.from('black_pages_categories').select('slug,name,description,sort_order').eq('active', true).order('sort_order').order('name'),
    client.from('black_pages_subcategories').select('category_slug,slug,name,target_per_city').eq('active', true).order('category_slug').order('name'),
  ])

  if (categoryResult.error || subcategoryResult.error) {
    return { categories: [], subcategories: [], error: 'Business categories could not be loaded.' }
  }

  return {
    categories: categoryResult.data ?? [],
    subcategories: subcategoryResult.data ?? [],
    error: null,
  }
}

export function subcategoriesFor(subcategories: readonly TaxonomySubcategory[], categorySlug: string) {
  return subcategories.filter(item => item.category_slug === categorySlug)
}
