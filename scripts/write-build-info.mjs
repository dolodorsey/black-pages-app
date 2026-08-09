#!/usr/bin/env node
/**
 * Writes public/build-info.json so the deployed commit is fetchable at
 * /build-info.json (the SPA equivalent of a /health endpoint).
 *
 * Commit resolution order: VITE_COMMIT_SHA, VERCEL_GIT_COMMIT_SHA, git rev-parse,
 * then 'unknown'. No secrets are written: only commit, build timestamp, and the
 * package name/version.
 */
import { execFileSync } from 'node:child_process'
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')

function gitCommit() {
  try {
    return execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
  } catch {
    return ''
  }
}

const pkg = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'))
const commit = (process.env.VITE_COMMIT_SHA || process.env.VERCEL_GIT_COMMIT_SHA || gitCommit() || 'unknown').trim()

const buildInfo = {
  name: pkg.name,
  version: pkg.version,
  commit,
  builtAt: new Date().toISOString(),
}

const target = resolve(root, 'public', 'build-info.json')
mkdirSync(dirname(target), { recursive: true })
writeFileSync(target, `${JSON.stringify(buildInfo, null, 2)}\n`)
console.log(`build-info: commit=${buildInfo.commit} builtAt=${buildInfo.builtAt}`)
