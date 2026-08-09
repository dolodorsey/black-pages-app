import assert from 'node:assert/strict'
import test from 'node:test'
import { DEFAULT_SUPABASE_URL, collectEnvProblems, readAppEnv } from '../src/lib/env.ts'

const VALID_KEY = 'sb_publishable_0123456789abcdef'

test('readAppEnv returns the parsed environment when the key is present', () => {
  const env = readAppEnv({ VITE_SUPABASE_PUBLISHABLE_KEY: VALID_KEY })
  assert.equal(env.supabasePublishableKey, VALID_KEY)
  assert.equal(env.supabaseUrl, DEFAULT_SUPABASE_URL)
  assert.equal(env.commitSha, 'unknown')
  assert.equal(env.builtAt, '')
})

test('readAppEnv honours an explicit project URL and build metadata', () => {
  const env = readAppEnv({
    VITE_SUPABASE_PUBLISHABLE_KEY: VALID_KEY,
    VITE_SUPABASE_URL: 'https://example.supabase.co',
    VITE_COMMIT_SHA: ' abc1234 ',
    VITE_BUILT_AT: '2026-08-09T12:00:00.000Z',
  })
  assert.equal(env.supabaseUrl, 'https://example.supabase.co')
  assert.equal(env.commitSha, 'abc1234')
  assert.equal(env.builtAt, '2026-08-09T12:00:00.000Z')
})

test('readAppEnv throws a useful message when the required key is missing', () => {
  assert.throws(
    () => readAppEnv({}),
    (thrown: unknown) => {
      assert.ok(thrown instanceof Error)
      assert.match(thrown.message, /cannot start/)
      assert.match(thrown.message, /VITE_SUPABASE_PUBLISHABLE_KEY is missing/)
      assert.match(thrown.message, /Required variables: VITE_SUPABASE_PUBLISHABLE_KEY/)
      return true
    },
  )
})

test('readAppEnv rejects an empty or whitespace-only key', () => {
  assert.throws(() => readAppEnv({ VITE_SUPABASE_PUBLISHABLE_KEY: '   ' }), /is missing/)
})

test('readAppEnv rejects a placeholder-length key', () => {
  assert.throws(() => readAppEnv({ VITE_SUPABASE_PUBLISHABLE_KEY: 'changeme' }), /malformed/)
})

test('readAppEnv rejects a key containing whitespace', () => {
  assert.throws(
    () => readAppEnv({ VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_012345 6789abcdef' }),
    /must not contain whitespace/,
  )
})

test('readAppEnv rejects a non-https or malformed project URL', () => {
  assert.throws(
    () => readAppEnv({ VITE_SUPABASE_PUBLISHABLE_KEY: VALID_KEY, VITE_SUPABASE_URL: 'http://example.supabase.co' }),
    /expected an https URL/,
  )
  assert.throws(
    () => readAppEnv({ VITE_SUPABASE_PUBLISHABLE_KEY: VALID_KEY, VITE_SUPABASE_URL: 'not-a-url' }),
    /expected an absolute https URL/,
  )
})

test('collectEnvProblems reports every problem at once', () => {
  const problems = collectEnvProblems({ VITE_SUPABASE_URL: 'ftp://example.com' })
  assert.equal(problems.length, 2)
  assert.ok(problems.some(problem => problem.includes('VITE_SUPABASE_PUBLISHABLE_KEY')))
  assert.ok(problems.some(problem => problem.includes('VITE_SUPABASE_URL')))
})

test('collectEnvProblems returns nothing for a valid environment', () => {
  assert.deepEqual(collectEnvProblems({ VITE_SUPABASE_PUBLISHABLE_KEY: VALID_KEY }), [])
})
