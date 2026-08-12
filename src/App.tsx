import { type FormEvent, useEffect, useMemo, useState } from 'react'
import {
  ArrowRight, Bookmark, BriefcaseBusiness, Building2, Check, ChevronRight, Grid2X2, Heart, Home,
  ListOrdered, LogIn, LogOut, Mail, MapPin, Navigation, Phone, Plus, Search, ShieldCheck, Store,
  UserRound, X, Globe2, Camera,
} from 'lucide-react'
import type { User } from '@supabase/supabase-js'
import { BuildInfoBadge } from './components/BuildInfoBadge'
import { BusinessApplicationModal } from './components/BusinessApplicationModal'
import { BusinessCard } from './components/BusinessCard'
import { CategoryBrowser, SubcategoryFilterRail } from './components/CategoryBrowser'
import { CategoryFilterRail, CategoryRail, DirectorySearchPanel } from './components/DirectoryControls'
import { LocationBrowser } from './components/LocationBrowser'
import { AppMark, EmptyState, Rating, StatusBadge } from './components/primitives'
import { labelCategory, labelSubcategory, pluralize } from './lib/categories.ts'
import { mapsUrl } from './lib/maps'
import { getAppEnv, getSupabaseClient } from './lib/supabase'
import {
  addFavorite, buildLocationGroups, countByCategory, countBySubcategory, distanceFrom, featuredBusinesses,
  fetchDirectory, fetchSavedDirectoryIds, filterDirectory, removeFavorite, submitOwnerClaim,
  type DirectoryBusiness, type DirectorySort, type GeoPoint,
} from './services/directory.ts'
import { fetchTaxonomy, subcategoriesFor, type TaxonomyCategory, type TaxonomySubcategory } from './services/taxonomy.ts'

type Tab = 'home' | 'directory' | 'categories' | 'saved' | 'account'

function getHoursSummary(business: DirectoryBusiness) {
  if (!business.hours || typeof business.hours !== 'object' || Array.isArray(business.hours)) return ''
  const summary = business.hours.summary
  return typeof summary === 'string' ? summary : ''
}

export default function App() {
  const supabase = useMemo(() => getSupabaseClient(), [])
  const supabaseUrl = useMemo(() => getAppEnv().supabaseUrl, [])

  const [businesses, setBusinesses] = useState<DirectoryBusiness[]>([])
  const [taxonomyCategories, setTaxonomyCategories] = useState<TaxonomyCategory[]>([])
  const [taxonomySubcategories, setTaxonomySubcategories] = useState<TaxonomySubcategory[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [tab, setTab] = useState<Tab>('home')
  const [query, setQuery] = useState('')
  const [location, setLocation] = useState('')
  const [category, setCategory] = useState('all')
  const [subcategory, setSubcategory] = useState('all')
  const [sort, setSort] = useState<DirectorySort>('recommended')
  const [nearPoint, setNearPoint] = useState<GeoPoint | null>(null)
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
  const [claimOpen, setClaimOpen] = useState(false)
  const [claimName, setClaimName] = useState('')
  const [claimEmail, setClaimEmail] = useState('')
  const [claimRole, setClaimRole] = useState('Owner')
  const [claimBusy, setClaimBusy] = useState(false)
  const [claimSuccess, setClaimSuccess] = useState(false)
  const [toast, setToast] = useState('')

  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const q = params.get('q') || ''
    const where = params.get('where') || ''
    const categoryParam = params.get('category') || 'all'
    const subcategoryParam = params.get('subcategory') || 'all'
    const sortParam = params.get('sort') === 'az' ? 'az' : 'recommended'
    setQuery(q)
    setLocation(where)
    setCategory(categoryParam)
    setSubcategory(subcategoryParam)
    setSort(sortParam)
    if (q || where || categoryParam !== 'all' || subcategoryParam !== 'all') setTab('directory')
  }, [])

  useEffect(() => {
    let active = true
    ;(async () => {
      const [directory, taxonomy, { data: sessionData }] = await Promise.all([
        fetchDirectory(supabase), fetchTaxonomy(supabase), supabase.auth.getSession(),
      ])
      if (!active) return
      if (directory.error) setError(directory.error)
      else setBusinesses(directory.businesses)
      if (taxonomy.error) setError(current => current || taxonomy.error || '')
      else {
        setTaxonomyCategories(taxonomy.categories)
        setTaxonomySubcategories(taxonomy.subcategories)
      }
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
    const timer = window.setTimeout(() => setToast(''), 2400)
    return () => window.clearTimeout(timer)
  }, [toast])

  useEffect(() => {
    if (tab !== 'directory') return
    const params = new URLSearchParams()
    if (query.trim()) params.set('q', query.trim())
    if (location.trim()) params.set('where', location.trim())
    if (category !== 'all') params.set('category', category)
    if (subcategory !== 'all') params.set('subcategory', subcategory)
    if (sort === 'az') params.set('sort', 'az')
    const next = `${window.location.pathname}${params.size ? `?${params.toString()}` : ''}`
    window.history.replaceState({}, '', next)
  }, [tab, query, location, category, subcategory, sort])

  const counts = useMemo(() => countByCategory(businesses), [businesses])
  const liveSubcategoryCounts = useMemo(() => new Map(countBySubcategory(businesses, category)), [businesses, category])
  const masterSubcategories = useMemo(() => subcategoriesFor(taxonomySubcategories, category), [taxonomySubcategories, category])
  const filtered = useMemo(() => filterDirectory(businesses, {
    category, subcategory, query, location, sort, near: nearPoint,
  }), [businesses, category, subcategory, query, location, sort, nearPoint])
  const featured = useMemo(() => featuredBusinesses(businesses), [businesses])
  const featuredRail = featured.length ? featured : businesses.slice(0, 8)
  const savedBusinesses = businesses.filter(business => savedIds.includes(business.directory_id))
  const locations = useMemo(() => buildLocationGroups(businesses), [businesses])
  const cityCount = locations.length
  const stateCount = new Set(locations.map(item => item.state).filter(Boolean)).size

  async function toggleFavorite(directoryId: string) {
    if (!user) { setAuthOpen(true); setToast('Sign in to save businesses.'); return }
    const currentlySaved = savedIds.includes(directoryId)
    setSavedIds(current => currentlySaved ? current.filter(id => id !== directoryId) : [...current, directoryId])
    if (currentlySaved) {
      const { error: favoriteError } = await removeFavorite(supabase, user.id, directoryId)
      if (favoriteError) setSavedIds(current => [...current, directoryId])
      else setToast('Removed from saved businesses.')
    } else {
      const { error: favoriteError } = await addFavorite(supabase, user.id, directoryId)
      if (favoriteError) setSavedIds(current => current.filter(id => id !== directoryId))
      else setToast('Business saved.')
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
      setToast(authMode === 'signin' ? 'Signed in.' : result.data.session ? 'Account created.' : 'Check your email to confirm your account.')
    }
    setAuthBusy(false)
  }

  async function submitClaim(event: FormEvent) {
    event.preventDefault()
    if (!selected) return
    if (!user) { setClaimOpen(false); setAuthOpen(true); return }
    setClaimBusy(true)
    const { error: claimError } = await submitOwnerClaim(supabase, {
      directoryId: selected.directory_id, claimantAuthId: user.id, claimantName: claimName,
      claimantEmail: claimEmail, roleAtBusiness: claimRole,
    })
    setClaimBusy(false)
    if (claimError) setToast(claimError)
    else setClaimSuccess(true)
  }

  function openBusiness(business: DirectoryBusiness) { setSelected(business) }

  function openDirectory(nextCategory = category, nextSubcategory = subcategory, nextSort: DirectorySort = sort) {
    setCategory(nextCategory)
    setSubcategory(nextSubcategory)
    setSort(nextSort)
    setTab('directory')
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  function selectLocation(value: string) {
    setLocation(value)
    setNearPoint(null)
    setSort('recommended')
    setTab('directory')
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  function useMyLocation() {
    if (!navigator.geolocation) { setToast('Location is not available in this browser.'); return }
    setToast('Finding Black-owned businesses near you…')
    navigator.geolocation.getCurrentPosition(
      position => {
        setNearPoint({ latitude: position.coords.latitude, longitude: position.coords.longitude })
        setLocation('')
        setSort('distance')
        setTab('directory')
        setToast('Showing businesses within 50 miles.')
      },
      () => setToast('Location permission was not available. Search by city or ZIP instead.'),
      { enableHighAccuracy: false, timeout: 9000, maximumAge: 300000 },
    )
  }

  function resetDirectory() {
    setQuery(''); setLocation(''); setCategory('all'); setSubcategory('all'); setSort('recommended'); setNearPoint(null)
  }

  const directoryHeading = nearPoint
    ? 'Black-owned businesses near you.'
    : location.trim()
      ? `Black-owned businesses in ${location.trim()}.`
      : 'Find Black-owned businesses.'

  return <div className="app-shell">
    <header className="topbar directory-topbar">
      <button className="brand-button" onClick={() => setTab('home')}>
        <img className="topbar-logo" src="/brand/black-pages-logo.webp" alt="" />
        <span><strong>THE BLACK PAGES</strong><small>Black-owned business directory</small></span>
      </button>
      <button className="avatar-button" aria-label="Account" onClick={() => user ? setTab('account') : setAuthOpen(true)}>
        {user ? (user.user_metadata?.full_name?.[0] || user.email?.[0] || 'U').toUpperCase() : <UserRound size={18} />}
      </button>
    </header>

    <main className="app-content directory-app-content">
      {tab === 'home' && <>
        <section className="directory-hero">
          <div className="directory-hero-shade" />
          <div className="directory-hero-content">
            <img src="/brand/black-pages-logo.webp" className="hero-brand-logo" alt="The Black Pages" />
            <span className="hero-kicker">THE BLACK-OWNED BUSINESS DIRECTORY</span>
            <h1>Find the business you need.</h1>
            <p>Search by business, service, category, city, neighborhood, or ZIP code.</p>
          </div>
        </section>

        <div className="home-search-wrap">
          <DirectorySearchPanel query={query} location={location} onQueryChange={setQuery} onLocationChange={value => { setLocation(value); setNearPoint(null) }} onSubmit={() => openDirectory()} onUseMyLocation={useMyLocation} nearActive={Boolean(nearPoint)} onClearNear={() => { setNearPoint(null); setSort('recommended') }} />
        </div>

        <section className="directory-quick-actions" aria-label="Directory shortcuts">
          <button onClick={() => setTab('categories')}><Grid2X2 /><span><strong>Categories</strong><small>{taxonomyCategories.length || 32} master categories</small></span><ChevronRight /></button>
          <button onClick={() => openDirectory('all', 'all', 'az')}><ListOrdered /><span><strong>A–Z Directory</strong><small>Browse every business</small></span><ChevronRight /></button>
          <button onClick={() => setApplicationOpen(true)}><Plus /><span><strong>Add a Business</strong><small>Build a complete listing</small></span><ChevronRight /></button>
          <button onClick={() => { setTab('directory'); setToast('Open a business profile to claim it.') }}><ShieldCheck /><span><strong>Claim a Business</strong><small>Manage an existing listing</small></span><ChevronRight /></button>
        </section>

        <section className="directory-stats" aria-label="Directory totals">
          <div><strong>{businesses.length}</strong><span>Businesses</span></div>
          <div><strong>{taxonomySubcategories.length}</strong><span>Business types</span></div>
          <div><strong>{cityCount}</strong><span>Cities / {stateCount} states</span></div>
        </section>

        <CategoryRail taxonomyCategories={taxonomyCategories} counts={counts} onSelectCategory={value => openDirectory(value, 'all')} onSeeAll={() => setTab('categories')} />
        <LocationBrowser locations={locations} onSelectLocation={selectLocation} />

        <section className="section-block featured-businesses-section">
          <div className="section-title"><div><span>DIRECTORY PICKS</span><h2>Featured businesses</h2><p>Complete Black-owned business profiles worth knowing.</p></div><button onClick={() => openDirectory('all', 'all')}>Full directory <ChevronRight size={15} /></button></div>
          <div className="horizontal-cards">{featuredRail.map(business => <BusinessCard compact key={business.directory_id} business={business} saved={savedIds.includes(business.directory_id)} onOpen={() => openBusiness(business)} onSave={() => toggleFavorite(business.directory_id)} />)}</div>
        </section>

        <section className="business-owner-banner">
          <div className="business-owner-banner-copy"><span>BUSINESS OWNERS</span><h2>Make sure customers can find you.</h2><p>Add category, services, phone, email, hours, address or service area, ZIP code, photos, and ownership evidence.</p></div>
          <div className="business-owner-banner-actions"><button onClick={() => setApplicationOpen(true)}><Plus size={16} /> Add business</button><button className="secondary" onClick={() => { setTab('directory'); setToast('Open your business profile and tap Claim this business.') }}><ShieldCheck size={16} /> Claim listing</button></div>
        </section>
      </>}

      {tab === 'directory' && <section className="directory-page directory-results-page">
        <div className="directory-page-heading"><span><Search size={14} /> BUSINESS DIRECTORY</span><h1>{directoryHeading}</h1><p>Search WHAT you need and WHERE you need it, or use your current location.</p></div>
        <DirectorySearchPanel compact query={query} location={location} onQueryChange={setQuery} onLocationChange={value => { setLocation(value); setNearPoint(null); if (sort === 'distance') setSort('recommended') }} onSubmit={() => undefined} onUseMyLocation={useMyLocation} nearActive={Boolean(nearPoint)} onClearNear={() => { setNearPoint(null); setSort('recommended') }} />

        <CategoryFilterRail taxonomyCategories={taxonomyCategories} counts={counts} category={category} onCategoryChange={value => { setCategory(value); setSubcategory('all') }} />
        {category !== 'all' && <SubcategoryFilterRail subcategories={masterSubcategories} liveCounts={liveSubcategoryCounts} subcategory={subcategory} onSubcategoryChange={setSubcategory} />}

        <div className="directory-result-tools">
          <div><strong>{pluralize(filtered.length, 'business', 'businesses')}</strong><small>{nearPoint ? ' within 50 miles' : query || location || category !== 'all' ? ' matching your search' : ' in the directory'}</small></div>
          <div className="directory-sort" aria-label="Sort businesses">
            <button className={sort === 'recommended' ? 'active' : ''} onClick={() => setSort('recommended')}>Recommended</button>
            <button className={sort === 'az' ? 'active' : ''} onClick={() => setSort('az')}>A–Z</button>
            {nearPoint && <button className={sort === 'distance' ? 'active' : ''} onClick={() => setSort('distance')}>Distance</button>}
          </div>
        </div>

        {loading ? <EmptyState icon={<Store />} title="Opening the directory" body="Loading Black-owned businesses." />
          : error ? <EmptyState icon={<Building2 />} title="Directory unavailable" body={error} />
          : filtered.length === 0 ? <EmptyState icon={<Search />} title="No businesses found" body="Try another business name, service, city, neighborhood, ZIP code, category, or radius." action={<button className="primary-action" onClick={resetDirectory}>Clear filters</button>} />
          : <div className="business-grid directory-business-grid">{filtered.map(business => <BusinessCard key={business.directory_id} business={business} saved={savedIds.includes(business.directory_id)} onOpen={() => openBusiness(business)} onSave={() => toggleFavorite(business.directory_id)} />)}</div>}
      </section>}

      {tab === 'categories' && <CategoryBrowser businesses={businesses} taxonomyCategories={taxonomyCategories} taxonomySubcategories={taxonomySubcategories} counts={counts} onBrowse={(nextCategory, nextSubcategory = 'all') => openDirectory(nextCategory, nextSubcategory)} />}

      {tab === 'saved' && <section className="directory-page saved-screen">
        <div className="directory-page-heading"><span><Bookmark size={14} /> SAVED BUSINESSES</span><h1>Your saved directory.</h1><p>Keep the businesses you want to find again in one place.</p></div>
        {!user ? <EmptyState icon={<Bookmark />} title="Sign in to save businesses" body="Create a personal list of Black-owned businesses you use or want to support." action={<button className="primary-action" onClick={() => setAuthOpen(true)}>Sign in <LogIn size={16} /></button>} />
          : savedBusinesses.length === 0 ? <EmptyState icon={<Heart />} title="No saved businesses yet" body="Save any business from the directory and it will appear here." action={<button className="primary-action" onClick={() => openDirectory('all', 'all')}>Browse directory <ArrowRight size={16} /></button>} />
          : <div className="business-grid directory-business-grid">{savedBusinesses.map(business => <BusinessCard key={business.directory_id} business={business} saved onOpen={() => openBusiness(business)} onSave={() => toggleFavorite(business.directory_id)} />)}</div>}
      </section>}

      {tab === 'account' && <section className="directory-page account-screen">
        <div className="account-card"><img src="/brand/black-pages-logo.webp" alt="" /><span>MY BLACK PAGES</span><h1>{user ? user.user_metadata?.full_name || user.email : 'Directory account'}</h1><p>{user ? 'Manage saved businesses and business listing actions.' : 'Sign in to save businesses and submit ownership claims.'}</p></div>
        <div className="profile-actions directory-account-actions">
          {!user && <button onClick={() => setAuthOpen(true)}><span><LogIn /><strong>Sign in or create account</strong><small>Save and claim business listings</small></span><ChevronRight /></button>}
          <button onClick={() => setApplicationOpen(true)}><span><BriefcaseBusiness /><strong>Add a Black-owned business</strong><small>Submit a complete directory profile</small></span><ChevronRight /></button>
          <button onClick={() => { setTab('directory'); setToast('Open the business profile you want to claim.') }}><span><ShieldCheck /><strong>Claim a business listing</strong><small>Request ownership of an existing profile</small></span><ChevronRight /></button>
          <button onClick={() => setTab('saved')}><span><Bookmark /><strong>Saved businesses</strong><small>{savedBusinesses.length} saved {savedBusinesses.length === 1 ? 'business' : 'businesses'}</small></span><ChevronRight /></button>
          {user && <button className="danger-action" onClick={async () => { await supabase.auth.signOut(); setTab('home'); setToast('Signed out.') }}><span><LogOut /><strong>Sign out</strong><small>{user.email}</small></span><ChevronRight /></button>}
        </div>
      </section>}
    </main>

    <nav className="bottom-nav directory-bottom-nav" aria-label="Primary navigation">
      {([['home', Home, 'Home'], ['directory', Search, 'Directory'], ['categories', Grid2X2, 'Categories'], ['saved', Bookmark, 'Saved'], ['account', UserRound, 'Account']] as const)
        .map(([id, Icon, label]) => <button key={id} className={tab === id ? 'active' : ''} onClick={() => setTab(id)}><Icon size={20} /><span>{label}</span></button>)}
    </nav>

    {selected && <div className="sheet-backdrop" onMouseDown={() => setSelected(null)}>
      <article className="business-sheet directory-business-sheet" onMouseDown={event => event.stopPropagation()}>
        <button className="sheet-close" onClick={() => setSelected(null)}><X /></button>
        <div className="sheet-image">{selected.image_url ? <img src={selected.image_url} alt="" /> : <div className="image-fallback"><Store /></div>}<div className="image-shade" /><StatusBadge business={selected} /></div>
        <div className="sheet-copy">
          <div className="card-meta"><span>{labelCategory(selected.category)}{selected.subcategory ? ` · ${labelSubcategory(selected.subcategory)}` : ''}</span><Rating business={selected} /></div>
          <h2>{selected.business_name}</h2>
          <p>{selected.short_description || `${labelCategory(selected.category)} in ${selected.city}.`}</p>
          <div className="sheet-location"><MapPin size={16} /><span><strong>{selected.neighborhood || selected.city}</strong><small>{selected.address || `${selected.city}${selected.state ? `, ${selected.state}` : ''}`}{selected.postal_code ? ` ${selected.postal_code}` : ''}</small>{selected.service_area && <small>Service area: {selected.service_area}</small>}</span></div>
          {nearPoint && distanceFrom(selected, nearPoint) != null && <div className="distance-note">Approximately {distanceFrom(selected, nearPoint)?.toFixed(1)} miles away</div>}
          <div className="quick-actions directory-quick-contact">
            {selected.phone && <a href={`tel:${selected.phone}`}><Phone /><span>Call</span></a>}
            {selected.business_email && <a href={`mailto:${selected.business_email}`}><Mail /><span>Email</span></a>}
            <a href={mapsUrl(selected)} target="_blank" rel="noreferrer"><Navigation /><span>Directions</span></a>
            {selected.website_url && <a href={selected.website_url} target="_blank" rel="noreferrer"><Globe2 /><span>Website</span></a>}
            {selected.instagram_handle && <a href={`https://instagram.com/${selected.instagram_handle.replace('@', '')}`} target="_blank" rel="noreferrer"><Camera /><span>Instagram</span></a>}
          </div>
          {selected.specialties.length > 0 && <div className="business-specialties"><strong>Services & specialties</strong><div>{selected.specialties.slice(0, 10).map(item => <span key={item}>{item}</span>)}</div></div>}
          {getHoursSummary(selected) && <div className="business-detail-row"><strong>Hours</strong><span>{getHoursSummary(selected)}</span></div>}
          <button className={`sheet-save ${savedIds.includes(selected.directory_id) ? 'saved' : ''}`} onClick={() => toggleFavorite(selected.directory_id)}><Bookmark fill={savedIds.includes(selected.directory_id) ? 'currentColor' : 'none'} /> {savedIds.includes(selected.directory_id) ? 'Saved business' : 'Save business'}</button>
          <button className="claim-button" onClick={() => { setClaimName(user?.user_metadata?.full_name || ''); setClaimEmail(user?.email || ''); setClaimOpen(true) }}><ShieldCheck /> Claim this business listing <ChevronRight /></button>
          <p className="profile-note">Business information comes from directory research and owner submissions. Confirm details directly with the business.</p>
        </div>
      </article>
    </div>}

    {authOpen && <div className="modal-backdrop" onMouseDown={() => setAuthOpen(false)}><form className="auth-modal" onSubmit={authenticate} onMouseDown={event => event.stopPropagation()}><button type="button" className="modal-close" onClick={() => setAuthOpen(false)}><X /></button><AppMark /><span className="eyebrow">MY BLACK PAGES</span><h2>{authMode === 'signin' ? 'Sign in.' : 'Create an account.'}</h2><p>Save businesses and claim business listings.</p><div className="segmented"><button type="button" className={authMode === 'signin' ? 'active' : ''} onClick={() => setAuthMode('signin')}>Sign in</button><button type="button" className={authMode === 'signup' ? 'active' : ''} onClick={() => setAuthMode('signup')}>Create account</button></div>{authMode === 'signup' && <label>Full name<input required value={authName} onChange={event => setAuthName(event.target.value)} /></label>}<label>Email<input required type="email" value={authEmail} onChange={event => setAuthEmail(event.target.value)} /></label><label>Password<input required minLength={8} type="password" value={authPassword} onChange={event => setAuthPassword(event.target.value)} /></label>{authError && <div className="form-error">{authError}</div>}<button className="primary-action" disabled={authBusy}>{authBusy ? 'Connecting…' : authMode === 'signin' ? 'Sign in' : 'Create account'} <ArrowRight size={16} /></button></form></div>}

    <BusinessApplicationModal open={applicationOpen} onClose={() => setApplicationOpen(false)} supabaseUrl={supabaseUrl} categories={taxonomyCategories} subcategories={taxonomySubcategories} onSubmitted={() => setToast('Business submitted for ownership and directory review.')} />

    {claimOpen && selected && <div className="modal-backdrop" onMouseDown={() => setClaimOpen(false)}><form className="auth-modal" onSubmit={submitClaim} onMouseDown={event => event.stopPropagation()}><button type="button" className="modal-close" onClick={() => setClaimOpen(false)}><X /></button>{claimSuccess ? <div className="success-state"><div className="success-check"><Check /></div><span>CLAIM RECEIVED</span><h2>We’ll verify your connection.</h2><p>The public listing will not change until your claim is reviewed.</p><button type="button" className="primary-action" onClick={() => { setClaimSuccess(false); setClaimOpen(false) }}>Done</button></div> : <><ShieldCheck className="modal-icon" /><span className="eyebrow">CLAIM BUSINESS</span><h2>{selected.business_name}</h2><p>Tell us your role at this business.</p><label>Your name<input required value={claimName} onChange={event => setClaimName(event.target.value)} /></label><label>Email<input required type="email" value={claimEmail} onChange={event => setClaimEmail(event.target.value)} /></label><label>Role at business<select value={claimRole} onChange={event => setClaimRole(event.target.value)}><option>Owner</option><option>Co-owner</option><option>Manager</option><option>Authorized representative</option></select></label><button className="primary-action" disabled={claimBusy}>{claimBusy ? 'Submitting…' : 'Submit claim'} <ArrowRight size={16} /></button></>}</form></div>}

    {toast && <div className="toast">{toast}</div>}
    <BuildInfoBadge />
  </div>
}
