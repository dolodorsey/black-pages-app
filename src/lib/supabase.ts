/**
 * Lazily constructed, fully typed Supabase client.
 *
 * Construction is deliberately lazy so that a missing or malformed
 * environment throws during React render (where the error boundary can show a
 * clear message) rather than during module evaluation, which would leave a
 * blank page.
 */
import { createClient } from '@supabase/supabase-js'
import type { Database } from './database.types'
import type { TypedSupabaseClient } from '../services/directory'
import { readAppEnv, type AppEnv } from './env'

let cachedEnv: AppEnv | null = null
let cachedClient: TypedSupabaseClient | null = null

/** Validated public environment. Throws a descriptive Error when invalid. */
export function getAppEnv(): AppEnv {
  if (!cachedEnv) cachedEnv = readAppEnv(import.meta.env as unknown as Record<string, unknown>)
  return cachedEnv
}

/** Singleton typed client. Throws a descriptive Error when the env is invalid. */
export function getSupabaseClient(): TypedSupabaseClient {
  if (!cachedClient) {
    const env = getAppEnv()
    cachedClient = createClient<Database>(env.supabaseUrl, env.supabasePublishableKey)
  }
  return cachedClient
}
