import { useEffect, useMemo, useState } from 'react'
import type { User } from '@supabase/supabase-js'
import { ArrowLeft, LockKeyhole } from 'lucide-react'
import { CoverageDashboard } from './components/CoverageDashboard'
import { getSupabaseClient } from './lib/supabase'

const staffRoles = new Set(['owner', 'admin', 'editor'])

export default function CoverageCommandCenterHost() {
  const supabase = useMemo(() => getSupabaseClient(), [])
  const [user, setUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let active = true
    supabase.auth.getSession().then(({ data }) => {
      if (!active) return
      setUser(data.session?.user || null)
      setLoading(false)
    })
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user || null)
      setLoading(false)
    })
    return () => { active = false; data.subscription.unsubscribe() }
  }, [supabase])

  const role = String(user?.app_metadata?.khg_role || '')
  const authorized = Boolean(user && staffRoles.has(role))

  if (loading) return <div className="app-shell"><main className="coverage-access"><span>THE BLACK PAGES</span><h1>Opening command center…</h1></main></div>

  if (!authorized) return <div className="app-shell"><main className="coverage-access"><LockKeyhole /><span>STAFF ONLY</span><h1>Coverage command center.</h1><p>Sign into THE BLACK PAGES with an owner, admin, or editor account before opening this dashboard.</p><a href="/"><ArrowLeft size={16} /> Return to directory</a></main></div>

  return <div className="app-shell">
    <header className="topbar directory-topbar">
      <a className="brand-button" href="/"><img className="topbar-logo" src="/brand/black-pages-logo.webp" alt="" /><span><strong>THE BLACK PAGES</strong><small>Coverage command center</small></span></a>
      <a className="coverage-back" href="/" aria-label="Return to directory"><ArrowLeft size={18} /></a>
    </header>
    <main className="app-content directory-app-content"><CoverageDashboard supabase={supabase} /></main>
  </div>
}
