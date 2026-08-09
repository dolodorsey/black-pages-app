/**
 * Deployed-build identification.
 *
 * `VITE_COMMIT_SHA` (falling back to `VERCEL_GIT_COMMIT_SHA`) is injected at
 * build time by `vite.config.ts`; the same values are written to
 * `public/build-info.json` by `scripts/write-build-info.mjs` so the deployed
 * commit is also fetchable at `/build-info.json` without shipping any secret.
 */
import type { EnvSource } from './env'

export type BuildInfo = {
  commit: string
  builtAt: string
}

declare global {
  interface Window {
    __BUILD_INFO__?: BuildInfo
  }
}

/** Pure reader so build info stays available even when validation fails. */
export function readBuildInfo(source: EnvSource): BuildInfo {
  const commit = typeof source.VITE_COMMIT_SHA === 'string' ? source.VITE_COMMIT_SHA.trim() : ''
  const builtAt = typeof source.VITE_BUILT_AT === 'string' ? source.VITE_BUILT_AT.trim() : ''
  return { commit: commit || 'unknown', builtAt }
}

export function getBuildInfo(): BuildInfo {
  return readBuildInfo(import.meta.env as unknown as EnvSource)
}

/** Exposes the build on `window.__BUILD_INFO__` for smoke checks and support. */
export function publishBuildInfo(): BuildInfo {
  const info = getBuildInfo()
  if (typeof window !== 'undefined') window.__BUILD_INFO__ = info
  return info
}
