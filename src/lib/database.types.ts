/** Minimal generated-style database types for THE BLACK PAGES client surface. */

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  public: {
    Tables: {
      black_pages_favorites: {
        Row: { user_auth_id: string; directory_id: string }
        Insert: { user_auth_id: string; directory_id: string }
        Update: { user_auth_id?: string; directory_id?: string }
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
      black_pages_categories: {
        Row: {
          slug: string
          name: string
          description: string | null
          sort_order: number
          active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          slug: string
          name: string
          description?: string | null
          sort_order?: number
          active?: boolean
        }
        Update: {
          slug?: string
          name?: string
          description?: string | null
          sort_order?: number
          active?: boolean
        }
        Relationships: []
      }
      black_pages_subcategories: {
        Row: {
          category_slug: string
          slug: string
          name: string
          target_per_city: number
          active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          category_slug: string
          slug: string
          name: string
          target_per_city?: number
          active?: boolean
        }
        Update: {
          category_slug?: string
          slug?: string
          name?: string
          target_per_city?: number
          active?: boolean
        }
        Relationships: []
      }
    }
    Views: {
      black_pages_directory_v2: {
        Row: {
          directory_id: string
          source_type: string
          source_id: string
          business_name: string
          slug: string
          category: string
          subcategory: string | null
          city: string
          state: string | null
          neighborhood: string | null
          address: string | null
          postal_code: string | null
          short_description: string | null
          website_url: string | null
          instagram_handle: string | null
          phone: string | null
          business_email: string | null
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
          hours: Json | null
          service_area: string | null
          specialties: string[] | null
          facebook_url: string | null
          linkedin_url: string | null
          tiktok_url: string | null
          serves_customers_at_location: boolean
          service_radius_miles: number | null
        }
        Relationships: []
      }
    }
    Functions: Record<never, never>
    Enums: Record<never, never>
    CompositeTypes: Record<never, never>
  }
}

export type DirectoryRow = Database['public']['Views']['black_pages_directory_v2']['Row']
