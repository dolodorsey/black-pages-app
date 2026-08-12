import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database, Json } from '../lib/database.types.ts'

export type CoverageCity = {
  city: string
  state: string
  launch_priority: number
  taxonomy_cells: number
  target_met_cells: number
  candidate_found_cells: number
  empty_cells: number
  city_launch_target: number
  published_business_slots: number
  candidate_slots: number
  remaining_gap: number
  taxonomy_coverage_pct: number
}

export type CoverageCell = {
  city: string
  state: string
  launch_priority: number
  category_slug: string
  category_name: string
  subcategory_slug: string
  subcategory_name: string
  target_count: number
  saturation_target: number
  published_count: number
  candidate_count: number
  gap_count: number
  discovery_gap: number
  coverage_status: 'covered' | 'candidate_found' | 'empty'
  coverage_pct: number
  priority_score: number
  city_launch_target: number
}

export type CoverageSnapshot = {
  cities: CoverageCity[]
  cells: CoverageCell[]
  enrichment: {
    total: number
    pending: number
    processing: number
    manual: number
    complete: number
    missing_location: number
  }
  gap_tasks: {
    total_gap_tasks: number
    open_gap_tasks: number
    empty_subcategory_tasks: number
    discovery_gap: number
  }
  generated_at: string
}

type TypedClient = SupabaseClient<Database>

function numberValue(value: unknown) {
  const number = Number(value)
  return Number.isFinite(number) ? number : 0
}

function arrayValue(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === 'object' && !Array.isArray(item)) : []
}

function coverageStatus(value: unknown): CoverageCell['coverage_status'] {
  if (value === 'covered' || value === 'candidate_found') return value
  return 'empty'
}

function parseSnapshot(value: Json): CoverageSnapshot {
  const root = value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, Json | undefined> : {}
  const cities: CoverageCity[] = arrayValue(root.cities).map(item => ({
    city: String(item.city || ''), state: String(item.state || ''), launch_priority: numberValue(item.launch_priority),
    taxonomy_cells: numberValue(item.taxonomy_cells), target_met_cells: numberValue(item.target_met_cells),
    candidate_found_cells: numberValue(item.candidate_found_cells), empty_cells: numberValue(item.empty_cells),
    city_launch_target: numberValue(item.city_launch_target), published_business_slots: numberValue(item.published_business_slots),
    candidate_slots: numberValue(item.candidate_slots), remaining_gap: numberValue(item.remaining_gap),
    taxonomy_coverage_pct: numberValue(item.taxonomy_coverage_pct),
  }))
  const cells: CoverageCell[] = arrayValue(root.cells).map(item => ({
    city: String(item.city || ''), state: String(item.state || ''), launch_priority: numberValue(item.launch_priority),
    category_slug: String(item.category_slug || ''), category_name: String(item.category_name || ''),
    subcategory_slug: String(item.subcategory_slug || ''), subcategory_name: String(item.subcategory_name || ''),
    target_count: numberValue(item.target_count), saturation_target: numberValue(item.saturation_target),
    published_count: numberValue(item.published_count), candidate_count: numberValue(item.candidate_count),
    gap_count: numberValue(item.gap_count), discovery_gap: numberValue(item.discovery_gap),
    coverage_status: coverageStatus(item.coverage_status),
    coverage_pct: numberValue(item.coverage_pct), priority_score: numberValue(item.priority_score), city_launch_target: numberValue(item.city_launch_target),
  }))
  const enrichmentRaw = root.enrichment && typeof root.enrichment === 'object' && !Array.isArray(root.enrichment) ? root.enrichment as Record<string, Json | undefined> : {}
  const gapRaw = root.gap_tasks && typeof root.gap_tasks === 'object' && !Array.isArray(root.gap_tasks) ? root.gap_tasks as Record<string, Json | undefined> : {}
  return {
    cities,
    cells,
    enrichment: {
      total: numberValue(enrichmentRaw.total), pending: numberValue(enrichmentRaw.pending), processing: numberValue(enrichmentRaw.processing),
      manual: numberValue(enrichmentRaw.manual), complete: numberValue(enrichmentRaw.complete), missing_location: numberValue(enrichmentRaw.missing_location),
    },
    gap_tasks: {
      total_gap_tasks: numberValue(gapRaw.total_gap_tasks), open_gap_tasks: numberValue(gapRaw.open_gap_tasks),
      empty_subcategory_tasks: numberValue(gapRaw.empty_subcategory_tasks), discovery_gap: numberValue(gapRaw.discovery_gap),
    },
    generated_at: String(root.generated_at || ''),
  }
}

export async function fetchCoverageSnapshot(supabase: TypedClient, city?: string | null) {
  const { data, error } = await supabase.rpc('black_pages_staff_coverage_snapshot', { p_city: city || null, p_limit: city ? 600 : 1000 })
  if (error || data == null) return { snapshot: null, error: error?.message || 'Coverage snapshot is unavailable.' }
  return { snapshot: parseSnapshot(data), error: '' }
}
