import { FormEvent, useEffect, useMemo, useState } from 'react'
import {
  ArrowLeft,
  ArrowRight,
  BadgeCheck,
  Bookmark,
  BriefcaseBusiness,
  Building2,
  Check,
  ChevronRight,
  Compass,
  ExternalLink,
  Globe2,
  Heart,
  Home,
  Instagram,
  LocateFixed,
  LogIn,
  LogOut,
  Map,
  MapPin,
  Navigation,
  Phone,
  Search,
  ShieldCheck,
  Sparkles,
  Star,
  Store,
  UserRound,
  X,
} from 'lucide-react'
import { createClient, type User } from '@supabase/supabase-js'

type DirectoryBusiness = {
  directory_id: string
  source_type: 'venue' | 'listing'
  source_id: string
  business_name: string
  slug: string
  category: string
  subcategory: string | null
  city: string
  state: string
  neighborhood: string | null
  address: string | null
  short_description: string | null
  website_url: string | null
  instagram_handle: string | null
  phone: string | null
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
}

type Tab = 'home' | 'discover' | 'map' | 'saved' | 'profile'

const supabaseUrl = 'https://dzlmtvodpyhetvektfuo.supabase.co'
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
const supabase = supabaseKey ? createClient(supabaseUrl, supabaseKey) : null

const categoryLabels: Record<string, string> = {
  restaurant: 'Restaurants',
  nightclub: 'Nightlife',
  brunch: 'Brunch',
  lounge: 'Lounges',
  hookah: 'Hookah',
  coffee: 'Coffee',
  culture: 'Arts & Culture',
  nightlife: 'Nightlife',
  beauty: 'Beauty',
  shopping: 'Shopping',
  fitness: 'Fitness',
  food_truck: 'Food Trucks',
  bar: 'Bars',
  comedy: 'Comedy',
  jazz: 'Jazz',
  spa: 'Spa',
  wellness: 'Wellness',
  special_events: 'Events',
  day_party: 'Day Parties',
}

const listingCategories = [
  'Food & Beverage',
  'Beauty & Wellness',
  'Professional Services',
  'Retail',
  'Arts & Culture',
  'Home Services',
  'Technology',
  'Automotive',
  'Health',
  'Education',
]

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

function labelCategory(value: string) {
  return categoryLabels[value] || value.replaceAll('_', ' ').replace(/\b\w/g, character => character.toUpperCase())
}

function mapsUrl(business: DirectoryBusiness) {
  if (business.latitude != null && business.longitude != null) {
    return `https://www.google.com/maps/search/?api=1&query=${business.latitude},${business.longitude}`
  }
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${business.business_name} ${business.address || business.city}`)}`
}

function AppMark() {
  return <div className="app-mark"><span>TBP</span></div>
}

function StatusBadge({ business }: { business: DirectoryBusiness }) {
  return business.owner_verified
    ? <span className="status-badge owner"><ShieldCheck size={12} /> Owner verified</span>
    : <span className="status-badge"><BadgeCheck size={12} /> Black-owned profile</span>
}

function Rating({ business }: { business: DirectoryBusiness }) {
  if (!business.rating) return <span className="rating quiet">New profile</span>
  return <span className="rating"><Star size={12} fill="currentColor" /> {Number(business.rating).toFixed(1)}{business.review_count ? <small>({business.review_count})</small> : null}</span>
}

function BusinessCard({ business, saved, onOpen, onSave, compact = false }: {
  business: DirectoryBusiness
  saved: boolean
  onOpen: () => void
  onSave: () => void
  compact?: boolean
}) {
  return <article className={`business-card ${compact ? 'compact' : ''}`} onClick={onOpen}>
    <div className="business-image">
      {business.image_url ? <img src={business.image_url} alt="" loading="lazy" /> : <div className="image-fallback"><Store /></div>}
      <div className="image-shade" />
      <button className={`save-button ${saved ? 'saved' : ''}`} aria-label={saved ? 'Remove from saved' : 'Save business'} onClick={event => { event.stopPropagation(); onSave() }}>
        <Bookmark size={17} fill={saved ? 'currentColor' : 'none'} />
      </button>
      <StatusBadge business={business} />
    </div>
    <div className="business-copy">
      <div className="card-meta"><span>{labelCategory(business.category)}</span><Rating business={business} /></div>
      <h3>{business.business_name}</h3>
      <p>{business.short_description || `${labelCategory(business.category)} in ${business.neighborhood || business.city}.`}</p>
      <div className="location-line"><MapPin size={13} /> {business.neighborhood ? `${business.neighborhood}, ` : ''}{business.city}</div>
    </div>
  </article>
}

function EmptyState({ icon, title, body, action }: { icon: React.ReactNode; title: string; body: string; action?: React.ReactNode }) {
  return <div className="empty-state">{icon}<h3>{title}</h3><p>{body}</p>{action}</div>
}

export default function App() {
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
      if (!supabase) {
        setError('The directory connection is not configured for this release.')
        setLoading(false)
        return
      }
      const [{ data, error: directoryError }, { data: sessionData }] = await Promise.all([
        supabase.from('black_pages_directory').select('*').order('featured', { ascending: false }).order('rating', { ascending: false, nullsFirst: false }).order('business_name'),
        supabase.auth.getSession(),
      ])
      if (!active) return
      if (directoryError) setError('The live directory could not be loaded.')
      else setBusinesses((data || []) as DirectoryBusiness[])
      setUser(sessionData.session?.user || null)
      setLoading(false)
    })()
    const { data: authSubscription } = supabase?.auth.onAuthStateChange((_event, session) => setUser(session?.user || null)) || { data: null }
    return () => { active = false; authSubscription?.subscription.unsubscribe() }
  }, [])

  useEffect(() => {
    if (!supabase || !user) { setSavedIds([]); return }
    supabase.from('black_pages_favorites').select('directory_id').eq('user_auth_id', user.id)
      .then(({ data }) => setSavedIds((data || []).map(item => item.directory_id)))
  }, [user])

  useEffect(() => {
    if (!toast) return
    const timer = window.setTimeout(() => setToast(''), 2200)
    return () => window.clearTimeout(timer)
  }, [toast])

  const categories = useMemo(() => {
    const counts = new Map<string, number>()
    businesses.forEach(business => counts.set(business.category, (counts.get(business.category) || 0) + 1))
    return [...counts.entries()].sort((a, b) => b[1] - a[1])
  }, [businesses])

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase()
    return businesses.filter(business => {
      const categoryMatch = category === 'all' || business.category === category
      const searchMatch = !needle || [business.business_name, business.category, business.subcategory, business.neighborhood, business.city, business.short_description, ...(business.tags || [])]
        .filter(Boolean).join(' ').toLowerCase().includes(needle)
      return categoryMatch && searchMatch
    })
  }, [businesses, category, query])

  const featured = businesses.filter(business => business.featured || Number(business.rating || 0) >= 4.5).slice(0, 8)
  const hero = featured[0] || businesses[0]
  const mapReady = filtered.filter(business => business.latitude != null && business.longitude != null)
  const savedBusinesses = businesses.filter(business => savedIds.includes(business.directory_id))

  async function toggleFavorite(directoryId: string) {
    if (!supabase || !user) { setAuthOpen(true); setToast('Sign in to save businesses.'); return }
    const currentlySaved = savedIds.includes(directoryId)
    setSavedIds(current => currentlySaved ? current.filter(id => id !== directoryId) : [...current, directoryId])
    if (currentlySaved) {
      const { error: favoriteError } = await supabase.from('black_pages_favorites').delete().eq('user_auth_id', user.id).eq('directory_id', directoryId)
      if (favoriteError) setSavedIds(current => [...current, directoryId])
      else setToast('Removed from saved.')
    } else {
      const { error: favoriteError } = await supabase.from('black_pages_favorites').insert({ user_auth_id: user.id, directory_id: directoryId })
      if (favoriteError) setSavedIds(current => current.filter(id => id !== directoryId))
      else setToast('Saved to your Black Pages.')
    }
  }

  async function authenticate(event: FormEvent) {
    event.preventDefault()
    if (!supabase || authBusy) return
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
    if (!supabase || !selected) return
    if (!user) { setClaimOpen(false); setAuthOpen(true); return }
    setClaimBusy(true)
    const { error: claimError } = await supabase.from('black_pages_claims').upsert({
      directory_id: selected.directory_id,
      claimant_auth_id: user.id,
      claimant_name: claimName,
      claimant_email: claimEmail,
      role_at_business: claimRole,
    }, { onConflict: 'directory_id,claimant_auth_id' })
    setClaimBusy(false)
    if (claimError) setToast(claimError.message)
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
            <button onClick={() => goDiscover()}><Search size={17} /> Explore {businesses.length || 135} businesses</button>
          </div>
        </section>

        <section className="floating-search">
          <Search size={19} />
          <input value={query} onChange={event => setQuery(event.target.value)} onFocus={() => setTab('discover')} placeholder="What are you looking for?" />
          <button aria-label="Use my location" onClick={() => { setTab('map'); setToast('Showing map-ready Black-owned businesses.') }}><LocateFixed size={18} /></button>
        </section>

        <section className="stats-strip">
          <div><strong>{businesses.length}</strong><span>Black-owned profiles</span></div>
          <div><strong>{categories.length}</strong><span>Categories</span></div>
          <div><strong>{businesses.filter(item => item.image_url).length}</strong><span>Visual profiles</span></div>
        </section>

        <section className="section-block">
          <div className="section-title"><div><span>EXPLORE</span><h2>Browse by category</h2></div><button onClick={() => goDiscover()}>See all <ChevronRight size={15} /></button></div>
          <div className="category-rail">
            {categories.slice(0, 10).map(([key, count]) => <button key={key} onClick={() => goDiscover(key)}>
              <span className="category-icon">{key === 'restaurant' || key === 'brunch' ? '🍽' : key === 'beauty' || key === 'spa' ? '✦' : key === 'nightclub' || key === 'lounge' ? '◐' : key === 'shopping' ? '◆' : '●'}</span>
              <strong>{labelCategory(key)}</strong><small>{count} businesses</small>
            </button>)}
          </div>
        </section>

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
        <div className="directory-search"><Search size={19} /><input autoFocus value={query} onChange={event => setQuery(event.target.value)} placeholder="Business, food, beauty, service, neighborhood…" />{query && <button onClick={() => setQuery('')}><X size={17} /></button>}</div>
        <div className="filter-rail"><button className={category === 'all' ? 'active' : ''} onClick={() => setCategory('all')}>All</button>{categories.map(([key, count]) => <button className={category === key ? 'active' : ''} key={key} onClick={() => setCategory(key)}>{labelCategory(key)} <small>{count}</small></button>)}</div>
        {loading ? <EmptyState icon={<Sparkles />} title="Opening the directory" body="Loading the live Black business network." /> : error ? <EmptyState icon={<Building2 />} title="Directory unavailable" body={error} /> : filtered.length === 0 ? <EmptyState icon={<Search />} title="No matches yet" body="Try another category, neighborhood, or search." /> : <div className="business-grid">{filtered.map(business => <BusinessCard key={business.directory_id} business={business} saved={savedIds.includes(business.directory_id)} onOpen={() => openBusiness(business)} onSave={() => toggleFavorite(business.directory_id)} />)}</div>}
      </section>}

      {tab === 'map' && <section className="map-screen">
        <div className="map-canvas">
          <iframe title="Black Pages business map" src="https://www.openstreetmap.org/export/embed.html?bbox=-84.58%2C33.62%2C-84.18%2C33.94&layer=mapnik" />
          <div className="map-shade" />
          <div className="map-search"><Search size={17} /><input value={query} onChange={event => setQuery(event.target.value)} placeholder="Search this area" /></div>
          <button className="recenter"><LocateFixed size={18} /></button>
          <div className="map-counter"><MapPin size={14} /> {mapReady.length} map-ready businesses</div>
        </div>
        <div className="map-results">
          <div className="section-title"><div><span>NEAR ATLANTA</span><h2>Explore the map</h2></div></div>
          <div className="horizontal-cards">{mapReady.slice(0, 20).map(business => <BusinessCard compact key={business.directory_id} business={business} saved={savedIds.includes(business.directory_id)} onOpen={() => openBusiness(business)} onSave={() => toggleFavorite(business.directory_id)} />)}</div>
        </div>
      </section>}

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
          {user && <button className="danger-action" onClick={async () => { await supabase?.auth.signOut(); setTab('home'); setToast('Signed out.') }}><span><LogOut /><strong>Sign out</strong><small>{user.email}</small></span><ChevronRight /></button>}
        </div>
      </section>}
    </main>

    <nav className="bottom-nav" aria-label="Primary navigation">
      {([
        ['home', Home, 'Home'],
        ['discover', Compass, 'Discover'],
        ['map', Map, 'Map'],
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
            {selected.instagram_handle && <a href={`https://instagram.com/${selected.instagram_handle.replace('@', '')}`} target="_blank" rel="noreferrer"><Instagram /><span>Instagram</span></a>}
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
  </div>
}
