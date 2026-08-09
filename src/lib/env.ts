/**
 * Startup validation for the public (VITE_*) environment.
 *
 * The app previously read `import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY`
 * directly and silently produced a null Supabase client when it was absent,
 * which surfaced to users as a generic "directory unavailable" screen. This
 * module instead fails loudly with an actionable message that the error
 * boundary renders.
 */

/** Env-like record. `import.meta.env` satisfies this. */
export type EnvSource = Record<string, unknown>

export type AppEnv = {
  /** Supabase project REST/auth origin. */
  supabaseUrl: string
  /** Publishable (anon) key. Safe to ship to the browser. */
  supabasePublishableKey: string
  /** Commit the bundle was built from, or 'unknown' outside CI. */
  commitSha: string
  /** ISO timestamp the bundle was built at, or '' when not injected. */
  builtAt: string
}

/**
 * Project URL the app has always pointed at. It stays a default so that an
 * existing deployment that only sets the key keeps working; when
 * VITE_SUPABASE_URL is provided it is validated like any other input.
 */
export const DEFAULT_SUPABASE_URL = 'https://dzlmtvodpyhetvektfuo.supabase.co'

/** Vars that have no safe default and must be present. */
export const REQUIRED_ENV_KEYS = ['VITE_SUPABASE_PUBLISHABLE_KEY'] as const

/** Shortest plausible publishable key; guards against placeholder values. */
const MIN_KEY_LENGTH = 20

function readString(source: EnvSource, key: string): string {
  const value = source[key]
  return typeof value === 'string' ? value.trim() : ''
}

function describeUrlProblem(key: string, value: string): string | null {
  let parsed: URL
  try {
    parsed = new URL(value)
  } catch {
    return `${key} is malformed: expected an absolute https URL, received "${value}".`
  }
  if (parsed.protocol !== 'https:') {
    return `${key} is malformed: expected an https URL, received protocol "${parsed.protocol}".`
  }
  return null
}

/**
 * Returns a human-readable problem for every missing or malformed variable.
 * Empty array means the environment is usable.
 */
export function collectEnvProblems(source: EnvSource): string[] {
  const problems: string[] = []

  const key = readString(source, 'VITE_SUPABASE_PUBLISHABLE_KEY')
  if (!key) {
    problems.push('VITE_SUPABASE_PUBLISHABLE_KEY is missing. Set it in the deployment environment.')
  } else if (/\s/.test(key)) {
    problems.push('VITE_SUPABASE_PUBLISHABLE_KEY is malformed: it must not contain whitespace.')
  } else if (key.length < MIN_KEY_LENGTH) {
    problems.push(
      `VITE_SUPABASE_PUBLISHABLE_KEY is malformed: expected at least ${MIN_KEY_LENGTH} characters, received ${key.length}.`,
    )
  }

  const url = readString(source, 'VITE_SUPABASE_URL')
  if (url) {
    const urlProblem = describeUrlProblem('VITE_SUPABASE_URL', url)
    if (urlProblem) problems.push(urlProblem)
  }

  return problems
}

/**
 * Parses and validates the public environment.
 *
 * @throws Error listing every problem when a required variable is missing or
 * malformed. The message is safe to show to an operator: it names variables
 * only, never values of secrets.
 */
export function readAppEnv(source: EnvSource): AppEnv {
  const problems = collectEnvProblems(source)
  if (problems.length > 0) {
    throw new Error(
      `THE BLACK PAGES cannot start: invalid environment configuration.\n${problems
        .map(problem => `- ${problem}`)
        .join('\n')}\nRequired variables: ${REQUIRED_ENV_KEYS.join(', ')}.`,
    )
  }

  return {
    supabaseUrl: readString(source, 'VITE_SUPABASE_URL') || DEFAULT_SUPABASE_URL,
    supabasePublishableKey: readString(source, 'VITE_SUPABASE_PUBLISHABLE_KEY'),
    commitSha: readString(source, 'VITE_COMMIT_SHA') || 'unknown',
    builtAt: readString(source, 'VITE_BUILT_AT'),
  }
}
