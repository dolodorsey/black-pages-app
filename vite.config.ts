import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

/**
 * Build identity. `scripts/write-build-info.mjs` runs first and writes
 * `public/build-info.json`; reading it back here keeps the value served at
 * /build-info.json identical to the one compiled into the bundle.
 */
function buildInfo() {
  try {
    const raw = readFileSync(fileURLToPath(new URL('./public/build-info.json', import.meta.url)), 'utf8')
    const parsed = JSON.parse(raw)
    if (typeof parsed.commit === 'string' && typeof parsed.builtAt === 'string') return parsed
  } catch {
    // No generated file (e.g. `vite dev`): fall through to the env/defaults.
  }
  return {
    commit: process.env.VITE_COMMIT_SHA || process.env.VERCEL_GIT_COMMIT_SHA || 'unknown',
    builtAt: new Date().toISOString(),
  }
}

const info = buildInfo()

export default defineConfig({
  plugins: [react()],
  define: {
    'import.meta.env.VITE_COMMIT_SHA': JSON.stringify(info.commit),
    'import.meta.env.VITE_BUILT_AT': JSON.stringify(info.builtAt),
  },
})
