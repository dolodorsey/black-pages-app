/**
 * Hand-written stand-in for `supabase gen types typescript`.
 *
 * This session has no Supabase CLI credentials, so these definitions were
 * derived strictly from the relations THE BLACK PAGES app actually reads and
 * writes (see `src/services/directory.ts`) plus the view/table definitions
 * committed under `supabase/migrations/`. No speculative columns are declared:
 * regenerate this file with the CLI once credentials are available.
 */

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  public: {
    Tables: {
      black_pages_favorites: {
        Row: {
          user_auth_id: string
          directory_id: string
        }
        Insert: {
          user_auth_id: string
          directory_id: string
        }
        Update: {
          user_auth_id?: string
          directory_id?: string
        }
        Relationships: []
      }
      black_pages_claims: {
        Row: {
          directory_id: string
          claimant_auth_id: string
          claimant_name: string | null
          claimant_email: string | null
          role_at_business: string | null
        }
        Insert: {
          directory_id: string
          claimant_auth_id: string
          claimant_name?: string | null
          claimant_email?: string | null
          role_at_business?: string | null
        }
        Update: {
          directory_id?: string
          claimant_auth_id?: string
          claimant_name?: string | null
          claimant_email?: string | null
          role_at_business?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      /**
       * `public.black_pages_directory` — union of published `gt_venues` rows
       * and approved `black_pages_listings` rows. Read-only for anon and
       * authenticated roles.
       */
      black_pages_directory: {
        Row: {
          directory_id: string
          source_type: string
          source_id: string
          business_name: string
          slug: string
          category: string
          subcategory: string | null
          city: string
          /** Null for cities the view has no state mapping for. */
          state: string | null
          neighborhood: string | null
          address: string | null
          short_description: string | null
          website_url: string | null
          instagram_handle: string | null
          phone: string | null
          image_url: string | null
          latitude: number | null
          longitude: number | null
          rating: number | null
          review_count: number | null
          price_range: string | null
          featured: boolean
          ownership_status: string
          owner_verified: boolean
          tags: string[] | null
        }
        Relationships: []
      }
    }
    Functions: Record<never, never>
    Enums: Record<never, never>
    CompositeTypes: Record<never, never>
  }
}

/** Raw row shape returned by PostgREST for the directory view. */
export type DirectoryRow = Database['public']['Views']['black_pages_directory']['Row']
