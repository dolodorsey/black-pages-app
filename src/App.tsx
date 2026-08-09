import { type FormEvent, useEffect, useMemo, useState } from 'react'
import {
  ArrowRight,
  Bookmark,
  BriefcaseBusiness,
  Building2,
  Check,
  ChevronRight,
  Compass,
  Globe2,
  Heart,
  Home,
  Camera,
  LogIn,
  LogOut,
  Map as MapIcon,
  MapPin,
  Navigation,
  Phone,
  Search,
  ShieldCheck,
  Sparkles,
  Store,
  UserRound,
  X,
} from 'lucide-react'
import type { User } from '@supabase/supabase-js'
import { BuildInfoBadge } from './components/BuildInfoBadge'
import { BusinessCard } from './components/BusinessCard'
import { CategoryFilterRail, CategoryRail, DirectorySearch, FloatingSearch } from './components/DirectoryControls'
import { MapPanel } from './components/MapPanel'
import { AppMark, EmptyState, Rating, StatusBadge } from './components/primitives'
import { labelCategory, listingCategories } from './lib/categories'
import { mapsUrl } from './lib/maps'
import { getAppEnv, getSupabaseClient } from './lib/supabase'
import {
  addFavorite,
  countByCategory,
  featuredBusinesses,
  fetchDirectory,
  fetchSavedDirectoryIds,
  filterDirectory,
  mapReadyBusinesses,
  removeFavorite,
  submitOwnerClaim,
  type DirectoryBusiness,
} from './services/directory'

type Tab = 'home' | 'discover' | 'map' | 'saved' | 'profile'

const emptyApplication = {
  businessName: '',
  ownerName: '',
  contactEmail: '',
  contactPhone: '',
  category: '',
  city: '',
  state: 'GA',
  websiteUrl: '',
  instagramHandle: '',
  description: '',
  ownershipCertification: false,
}

export default function App() {
  // Throws when the public environment is missing or malformed; ErrorBoundary
  // renders the explanation instead of a blank page.
  const supabase = useMemo(() => getSupabaseClient(), [])
  const supabaseUrl = useMemo(() => getAppEnv().supabaseUrl, [])

  const [businesses, setBusinesses] = useState<DirectoryBusiness[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [tab, setTab] = useState<Tab>('home')
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('all')
  const [selected, setSelected] = useState<DirectoryBusiness | null>(null)
  const [savedIds, setSavedIds] = useState<string[]>([])
  const [user, setUser] = useState<User | null>(null)
  const [authOpen, setAuthOpen] = useState(false)
  const [authMode, setAuthMode] = useState<'signin' | 'signup'>('signin')
  const [authEmail, setAuthEmail] = useState('')
  const [authPassword, setAuthPassword] = useState('')
  const [authName, setAuthName] = useState('')
  const [authBusy, setAuthBusy] = useState(false)
  const [authError, setAuthError] = useState('')
  const [applicationOpen, setApplicationOpen] = useState(false)
  const [application, setApplication] = useState(emptyApplication)
  const [applicationBusy, setApplicationBusy] = useState(false)
  const [applicationSuccess, setApplicationSuccess] = useState(false)
  const [applicationError, setApplicationError] = useState('')
  const [claimOpen, setClaimOpen] = useState(false)
  const [claimName, setClaimName] = useState('')
  const [claimEmail, setClaimEmail] = useState('')
  const [claimRole, setClaimRole] = useState('Owner')
  const [claimBusy, setClaimBusy] = useState(false)
  const [claimSuccess, setClaimSuccess] = useState(false)
  const [toast, setToast] = useState('')

  useEffect(() => {
    let active = true
    ;(async () => {
      const [directory, { data: sessionData }] = await Promise.all([
        fetchDirectory(supabase),
        supabase.auth.getSession(),
      ])
      if (!active) return
      if (directory.error) setError(directory.error)
      else setBusinesses(directory.businesses)
      setUser(sessionData.session?.user || null)
      setLoading(false)
    })()
    const { data: authSubscription } = supabase.auth.onAuthStateChange((_event, session) => setUser(session?.user || null))
    return () => { active = false; authSubscription?.subscription.unsubscribe() }
  }, [supabase])

  useEffect(() => {
    if (!user) { setSavedIds([]); return }
    fetchSavedDirectoryIds(supabase, user.id).then(setSavedIds)
  }, [supabase, user])

  useEffect(() => {
    if (!toast) return
    const timer = window.setTimeout(() => setToast(''), 2200)
    return () => window.clearTimeout(timer)
  }, [toast])

  const categories = useMemo(() => countByCategory(businesses), [businesses])
  const filtered = useMemo(() => filterDirectory(businesses, { category, query }), [businesses, category, query])

  const featured = featuredBusinesses(businesses)
  const hero = featured[0] || businesses[0]
  const mapReady = mapReadyBusinesses(filtered)
  const savedBusinesses = businesses.filter(business => savedIds.includes(business.directory_id))
  // Never invent a total: show the real published count, or nothing at all.
  const directoryCount = businesses.length
  const exploreLabel = directoryCount > 0 ? `Explore ${directoryCount} businesses` : 'Explore the directory'

  async function toggleFavorite(directoryId: string) {
    if (!user) { setAuthOpen(true); setToast('Sign in to save businesses.'); return }
    const currentlySaved = savedIds.includes(directoryId)
    setSavedIds(current => currentlySaved ? current.filter(id => id !== directoryId) : [...current, directoryId])
    if (currentlySaved) {
      const { error: favoriteError } = await removeFavorite(supabase, user.id, directoryId)
      if (favoriteError) setSavedIds(current => [...current, directoryId])
      else setToast('Removed from saved.')
    } else {
      const { error: favoriteError } = await addFavorite(supabase, user.id, directoryId)
      if (favoriteError) setSavedIds(current => current.filter(id => id !== directoryId))
      else setToast('Saved to your Black Pages.')
    }
  }

  async function authenticate(event: FormEvent) {
    event.preventDefault()
    if (authBusy) return
    setAuthBusy(true); setAuthError('')
    const result = authMode === 'signin'
      ? await supabase.auth.signInWithPassword({ email: authEmail.trim(), password: authPassword })
      : await supabase.auth.signUp({ email: authEmail.trim(), password: authPassword, options: { data: { full_name: authName.trim(), app: 'black_pages' } } })
    if (result.error) setAuthError(result.error.message)
    else {
      setAuthOpen(false)
      setToast(authMode === 'signin' ? 'Welcome back.' : result.data.session ? 'Account created.' : 'Check your email to confirm your account.')
    }
    setAuthBusy(false)
  }

  async function submitApplication(event: FormEvent) {
    event.preventDefault()
    setApplicationBusy(true); setApplicationError('')
    try {
      const response = await fetch(`${supabaseUrl}/functions/v1/black-pages-application`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(application),
      })
      const body = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(body.error || 'Application could not be submitted.')
      setApplicationSuccess(true)
      setApplication(emptyApplication)
    } catch (submissionError) {
      setApplicationError(submissionError instanceof Error ? submissionError.message : 'Application could not be submitted.')
    } finally {
      setApplicationBusy(false)
    }
  }

  async function submitClaim(event: FormEvent) {
    event.preventDefault()
    if (!selected) return
    if (!user) { setClaimOpen(false); setAuthOpen(true); return }
    setClaimBusy(true)
    const { error: claimError } = await submitOwnerClaim(supabase, {
      directoryId: selected.directory_id,
      claimantAuthId: user.id,
      claimantName: claimName,
      claimantEmail: claimEmail,
      roleAtBusiness: claimRole,
    })
    setClaimBusy(false)
    if (claimError) setToast(claimError)
    else setClaimSuccess(true)
  }

  function openBusiness(business: DirectoryBusiness) {
    setSelected(business)
  }

  function goDiscover(nextCategory = 'all') {
    setCategory(nextCategory)
    setTab('discover')
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  return <div className="app-shell">
    <header className="topbar">
      <button className="brand-button" onClick={() => setTab('home')}><AppMark /><span><strong>THE BLACK PAGES</strong><small>Digital Black business network</small></span></button>
      <button className="avatar-button" onClick={() => user ? setTab('profile') : setAuthOpen(true)}>{user ? (user.user_metadata?.full_name?.[0] || user.email?.[0] || 'U').toUpperCase() : <UserRound size={18} />}</button>
    </header>

    <main className="app-content">
      {tab === 'home' && <>
        <section className="home-hero" style={hero?.image_url ? { backgroundImage: `url(${hero.image_url})` } : undefined}>
          <div className="hero-overlay" />
          <div className="hero-content">
            <span className="eyebrow"><Sparkles size={13} /> THE NEW DIGITAL BLACK PAGES</span>
            <h1>Every Black-owned business.<br/><em>One powerful network.</em></h1>
            <p>Search, save, support, review, and connect with Black-owned businesses around you.</p>
            <button onClick={() => goDiscover()}><Search size={17} /> {exploreLabel}</button>
          </div>
        </section>

        <FloatingSearch
          query={query}
          onQueryChange={setQuery}
          onFocus={() => setTab('discover')}
          onUseLocation={() => { setTab('map'); setToast('Showing map-ready Black-owned businesses.') }}
        />

        <section className="stats-strip">
          <div><strong>{businesses.length}</strong><span>Black-owned profiles</span></div>
          <div><strong>{categories.length}</strong><span>Categories</span></div>
          <div><strong>{businesses.filter(item => item.image_url).length}</strong><span>Visual profiles</span></div>
        </section>

        <CategoryRail categories={categories} onSelectCategory={goDiscover} onSeeAll={() => goDiscover()} />

        <section className="section-block dark-section">
          <div className="section-title"><div><span>TOP PROFILES</span><h2>Popular in Atlanta</h2></div></div>
          <div className="horizontal-cards">
            {(featured.length ? featured : businesses).slice(0, 8).map(business => <BusinessCard compact key={business.directory_id} business={business} saved={savedIds.includes(business.directory_id)} onOpen={() => openBusiness(business)} onSave={() => toggleFavorite(business.directory_id)} />)}
          </div>
        </section>

        <section className="network-banner">
          <div><span>FOR BUSINESS OWNERS</span><h2>Own your profile.<br/>Grow your reach.</h2><p>Claim an existing page or submit a new Black-owned business for review.</p></div>
          <button onClick={() => setApplicationOpen(true)}>Add your business <ArrowRight size={16} /></button>
        </section>
      </>}

      {tab === 'discover' && <section className="discover-screen">
        <div className="screen-heading"><span>DIRECTORY</span><h1>Find Black-owned.</h1><p>{filtered.length} results across Atlanta</p></div>
        <DirectorySearch query={query} onQueryChange={setQuery} />
        <CategoryFilterRail categories={categories} category={category} onCategoryChange={setCategory} />
        {loading ? <EmptyState icon={<Sparkles />} title="Opening the directory" body="Loading the live Black business network." /> : error ? <EmptyState icon={<Building2 />} title="Directory unavailable" body={error} /> : filtered.length === 0 ? <EmptyState icon={<Search />} title="No matches yet" body="Try another category, neighborhood, or search." /> : <div className="business-grid">{filtered.map(business => <BusinessCard key={business.directory_id} business={business} saved={savedIds.includes(business.directory_id)} onOpen={() => openBusiness(business)} onSave={() => toggleFavorite(business.directory_id)} />)}</div>}
      </section>}

      {tab === 'map' && <MapPanel
        query={query}
        onQueryChange={setQuery}
        mapReady={mapReady}
        savedIds={savedIds}
        onOpen={openBusiness}
        onSave={toggleFavorite}
      />}

      {tab === 'saved' && <section className="saved-screen">
        <div className="screen-heading"><span>MY BLACK PAGES</span><h1>Saved businesses.</h1><p>Your personal Black-owned business network.</p></div>
        {!user ? <EmptyState icon={<Bookmark />} title="Sign in to build your Pages" body="Save businesses, submit reviews, and claim business profiles." action={<button className="primary-action" onClick={() => setAuthOpen(true)}>Sign in <LogIn size={16} /></button>} /> : savedBusinesses.length === 0 ? <EmptyState icon={<Heart />} title="Nothing saved yet" body="Tap the bookmark on any business to build your personal directory." action={<button className="primary-action" onClick={() => goDiscover()}>Explore businesses <ArrowRight size={16} /></button>} /> : <div className="business-grid">{savedBusinesses.map(business => <BusinessCard key={business.directory_id} business={business} saved onOpen={() => openBusiness(business)} onSave={() => toggleFavorite(business.directory_id)} />)}</div>}
      </section>}

      {tab === 'profile' && <section className="profile-screen">
        <div className="profile-hero"><AppMark /><span>YOUR NETWORK</span><h1>{user ? user.user_metadata?.full_name || user.email : 'Join The Black Pages'}</h1><p>{user ? 'Save businesses, claim profiles, and help strengthen the directory.' : 'Create an account to personalize your Black business network.'}</p></div>
        <div className="profile-actions">
          {!user && <button onClick={() => setAuthOpen(true)}><span><LogIn /><strong>Sign in or create account</strong><small>Save, review, and claim profiles</small></span><ChevronRight /></button>}
          <button onClick={() => setApplicationOpen(true)}><span><BriefcaseBusiness /><strong>List a Black-owned business</strong><small>Submit a new business for review</small></span><ChevronRight /></button>
          <button onClick={() => { setTab('discover'); setToast('Open a business profile to submit a claim.') }}><span><ShieldCheck /><strong>Claim an existing profile</strong><small>Unlock owner verification and profile controls</small></span><ChevronRight /></button>
          <button onClick={() => setTab('saved')}><span><Bookmark /><strong>Saved businesses</strong><small>{savedBusinesses.length} profiles in your Pages</small></span><ChevronRight /></button>
          {user && <button className="danger-action" onClick={async () => { await supabase.auth.signOut(); setTab('home'); setToast('Signed out.') }}><span><LogOut /><strong>Sign out</strong><small>{user.email}</small></span><ChevronRight /></button>}
        </div>
      </section>}
    </main>

    <nav className="bottom-nav" aria-label="Primary navigation">
      {([
        ['home', Home, 'Home'],
        ['discover', Compass, 'Discover'],
        ['map', MapIcon, 'Map'],
        ['saved', Bookmark, 'Saved'],
        ['profile', UserRound, 'Profile'],
      ] as const).map(([id, Icon, label]) => <button key={id} className={tab === id ? 'active' : ''} onClick={() => setTab(id)}><Icon size={20} /><span>{label}</span></button>)}
    </nav>

    {selected && <div className="sheet-backdrop" onMouseDown={() => setSelected(null)}>
      <article className="business-sheet" onMouseDown={event => event.stopPropagation()}>
        <button className="sheet-close" onClick={() => setSelected(null)}><X /></button>
        <div className="sheet-image">{selected.image_url ? <img src={selected.image_url} alt="" /> : <div className="image-fallback"><Store /></div>}<div className="image-shade" /><StatusBadge business={selected} /></div>
        <div className="sheet-copy">
          <div className="card-meta"><span>{labelCategory(selected.category)}</span><Rating business={selected} /></div>
          <h2>{selected.business_name}</h2>
          <p>{selected.short_description || `Discover this Black-owned ${labelCategory(selected.category).toLowerCase()} business in ${selected.city}.`}</p>
          <div className="sheet-location"><MapPin size={16} /><span><strong>{selected.neighborhood || selected.city}</strong><small>{selected.address || `${selected.city}, ${selected.state}`}</small></span></div>
          <div className="quick-actions">
            {selected.phone && <a href={`tel:${selected.phone}`}><Phone /><span>Call</span></a>}
            <a href={mapsUrl(selected)} target="_blank" rel="noreferrer"><Navigation /><span>Directions</span></a>
            {selected.website_url && <a href={selected.website_url} target="_blank" rel="noreferrer"><Globe2 /><span>Website</span></a>}
            {selected.instagram_handle && <a href={`https://instagram.com/${selected.instagram_handle.replace('@', '')}`} target="_blank" rel="noreferrer"><Camera /><span>Instagram</span></a>}
          </div>
          <button className={`sheet-save ${savedIds.includes(selected.directory_id) ? 'saved' : ''}`} onClick={() => toggleFavorite(selected.directory_id)}><Bookmark fill={savedIds.includes(selected.directory_id) ? 'currentColor' : 'none'} /> {savedIds.includes(selected.directory_id) ? 'Saved to My Black Pages' : 'Save to My Black Pages'}</button>
          <button className="claim-button" onClick={() => { setClaimName(user?.user_metadata?.full_name || ''); setClaimEmail(user?.email || ''); setClaimOpen(true) }}><ShieldCheck /> Own this business? Claim this profile <ChevronRight /></button>
          <p className="profile-note">Directory information is sourced from enterprise business intelligence and owner submissions. Confirm details directly with each business.</p>
        </div>
      </article>
    </div>}

    {authOpen && <div className="modal-backdrop" onMouseDown={() => setAuthOpen(false)}><form className="auth-modal" onSubmit={authenticate} onMouseDown={event => event.stopPropagation()}><button type="button" className="modal-close" onClick={() => setAuthOpen(false)}><X /></button><AppMark /><span className="eyebrow">MY BLACK PAGES</span><h2>{authMode === 'signin' ? 'Welcome back.' : 'Build your network.'}</h2><p>Save businesses, submit reviews, and claim your business profile.</p><div className="segmented"><button type="button" className={authMode === 'signin' ? 'active' : ''} onClick={() => setAuthMode('signin')}>Sign in</button><button type="button" className={authMode === 'signup' ? 'active' : ''} onClick={() => setAuthMode('signup')}>Create account</button></div>{authMode === 'signup' && <label>Full name<input required value={authName} onChange={event => setAuthName(event.target.value)} /></label>}<label>Email<input required type="email" value={authEmail} onChange={event => setAuthEmail(event.target.value)} /></label><label>Password<input required minLength={8} type="password" value={authPassword} onChange={event => setAuthPassword(event.target.value)} /></label>{authError && <div className="form-error">{authError}</div>}<button className="primary-action" disabled={authBusy}>{authBusy ? 'Connecting…' : authMode === 'signin' ? 'Sign in' : 'Create account'} <ArrowRight size={16} /></button></form></div>}

    {applicationOpen && <div className="modal-backdrop" onMouseDown={() => setApplicationOpen(false)}><form className="application-modal" onSubmit={submitApplication} onMouseDown={event => event.stopPropagation()}><button type="button" className="modal-close" onClick={() => setApplicationOpen(false)}><X /></button>{applicationSuccess ? <div className="success-state"><div className="success-check"><Check /></div><span>APPLICATION RECEIVED</span><h2>Your business is in review.</h2><p>It will not appear publicly until the ownership and business details are reviewed.</p><button type="button" className="primary-action" onClick={() => { setApplicationSuccess(false); setApplicationOpen(false) }}>Done</button></div> : <><span className="eyebrow">BUSINESS APPLICATION</span><h2>Join The Black Pages.</h2><p>Submit accurate public business information. Approval is not automatic.</p><div className="form-grid"><label>Business name<input required value={application.businessName} onChange={event => setApplication({ ...application, businessName: event.target.value })} /></label><label>Owner/contact name<input required value={application.ownerName} onChange={event => setApplication({ ...application, ownerName: event.target.value })} /></label><label>Email<input required type="email" value={application.contactEmail} onChange={event => setApplication({ ...application, contactEmail: event.target.value })} /></label><label>Phone<input value={application.contactPhone} onChange={event => setApplication({ ...application, contactPhone: event.target.value })} /></label><label>Category<select required value={application.category} onChange={event => setApplication({ ...application, category: event.target.value })}><option value="">Choose category</option>{listingCategories.map(item => <option key={item}>{item}</option>)}</select></label><label>City<input required value={application.city} onChange={event => setApplication({ ...application, city: event.target.value })} /></label><label>State<input required maxLength={2} value={application.state} onChange={event => setApplication({ ...application, state: event.target.value.toUpperCase() })} /></label><label>Website<input type="url" placeholder="https://" value={application.websiteUrl} onChange={event => setApplication({ ...application, websiteUrl: event.target.value })} /></label><label>Instagram<input placeholder="@handle" value={application.instagramHandle} onChange={event => setApplication({ ...application, instagramHandle: event.target.value })} /></label><label className="wide">Description<textarea required maxLength={1200} value={application.description} onChange={event => setApplication({ ...application, description: event.target.value })} /></label><label className="certify wide"><input required type="checkbox" checked={application.ownershipCertification} onChange={event => setApplication({ ...application, ownershipCertification: event.target.checked })} /><span>I certify that this business is Black-owned and that I am authorized to submit it.</span></label></div>{applicationError && <div className="form-error">{applicationError}</div>}<button className="primary-action" disabled={applicationBusy}>{applicationBusy ? 'Submitting…' : 'Submit for review'} <ArrowRight size={16} /></button></>}</form></div>}

    {claimOpen && selected && <div className="modal-backdrop" onMouseDown={() => setClaimOpen(false)}><form className="auth-modal" onSubmit={submitClaim} onMouseDown={event => event.stopPropagation()}><button type="button" className="modal-close" onClick={() => setClaimOpen(false)}><X /></button>{claimSuccess ? <div className="success-state"><div className="success-check"><Check /></div><span>CLAIM RECEIVED</span><h2>We’ll verify your connection.</h2><p>Your profile will not change until the claim is reviewed.</p><button type="button" className="primary-action" onClick={() => { setClaimSuccess(false); setClaimOpen(false) }}>Done</button></div> : <><ShieldCheck className="modal-icon" /><span className="eyebrow">CLAIM BUSINESS PROFILE</span><h2>{selected.business_name}</h2><p>Tell us who you are. Supporting proof can be requested during review.</p><label>Your name<input required value={claimName} onChange={event => setClaimName(event.target.value)} /></label><label>Email<input required type="email" value={claimEmail} onChange={event => setClaimEmail(event.target.value)} /></label><label>Role at business<select value={claimRole} onChange={event => setClaimRole(event.target.value)}><option>Owner</option><option>Co-owner</option><option>Manager</option><option>Authorized representative</option></select></label><button className="primary-action" disabled={claimBusy}>{claimBusy ? 'Submitting…' : 'Submit claim'} <ArrowRight size={16} /></button></>}</form></div>}

    {toast && <div className="toast">{toast}</div>}
    <BuildInfoBadge />
  </div>
}
