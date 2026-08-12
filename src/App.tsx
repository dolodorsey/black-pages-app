import { type FormEvent, useEffect, useMemo, useState } from 'react'
import {
  ArrowRight,
  Bookmark,
  BriefcaseBusiness,
  Building2,
  Check,
  ChevronRight,
  Grid2X2,
  Heart,
  Home,
  ListOrdered,
  LogIn,
  LogOut,
  MapPin,
  Navigation,
  Phone,
  Plus,
  Search,
  ShieldCheck,
  Store,
  UserRound,
  X,
  Globe2,
  Camera,
} from 'lucide-react'
import type { User } from '@supabase/supabase-js'
import { BuildInfoBadge } from './components/BuildInfoBadge'
import { BusinessCard } from './components/BusinessCard'
import { CategoryBrowser, SubcategoryFilterRail } from './components/CategoryBrowser'
import { CategoryFilterRail, CategoryRail, DirectorySearchPanel } from './components/DirectoryControls'
import { AppMark, EmptyState, Rating, StatusBadge } from './components/primitives'
import { labelCategory, labelSubcategory, listingCategories, pluralize } from './lib/categories'
import { mapsUrl } from './lib/maps'
import { getAppEnv, getSupabaseClient } from './lib/supabase'
import {
  addFavorite,
  countByCategory,
  countBySubcategory,
  featuredBusinesses,
  fetchDirectory,
  fetchSavedDirectoryIds,
  filterDirectory,
  removeFavorite,
  submitOwnerClaim,
  type DirectoryBusiness,
  type DirectorySort,
} from './services/directory'

type Tab = 'home' | 'directory' | 'categories' | 'saved' | 'account'

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
  const supabase = useMemo(() => getSupabaseClient(), [])
  const supabaseUrl = useMemo(() => getAppEnv().supabaseUrl, [])

  const [businesses, setBusinesses] = useState<DirectoryBusiness[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [tab, setTab] = useState<Tab>('home')
  const [query, setQuery] = useState('')
  const [location, setLocation] = useState('')
  const [category, setCategory] = useState('all')
  const [subcategory, setSubcategory] = useState('all')
  const [sort, setSort] = useState<DirectorySort>('recommended')
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
  const subcategories = useMemo(() => countBySubcategory(businesses, category), [businesses, category])
  const filtered = useMemo(
    () => filterDirectory(businesses, { category, subcategory, query, location, sort }),
    [businesses, category, subcategory, query, location, sort],
  )
  const featured = useMemo(() => featuredBusinesses(businesses), [businesses])
  const featuredRail = featured.length ? featured : businesses.slice(0, 8)
  const savedBusinesses = businesses.filter(business => savedIds.includes(business.directory_id))
  const cityCount = new Set(businesses.map(item => item.city.trim()).filter(Boolean)).size

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
      if (!response.ok) throw new Error(body.error || 'Business could not be submitted.')
      setApplicationSuccess(true)
      setApplication(emptyApplication)
    } catch (submissionError) {
      setApplicationError(submissionError instanceof Error ? submissionError.message : 'Business could not be submitted.')
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

  function openDirectory(nextCategory = 'all', nextSubcategory = 'all', nextSort: DirectorySort = sort) {
    setCategory(nextCategory)
    setSubcategory(nextSubcategory)
    setSort(nextSort)
    setTab('directory')
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  function resetDirectory() {
    setQuery('')
    setLocation('')
    setCategory('all')
    setSubcategory('all')
    setSort('recommended')
  }

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
            <p>Search Black-owned businesses by name, service, category, city, or neighborhood.</p>
          </div>
        </section>

        <div className="home-search-wrap">
          <DirectorySearchPanel
            query={query}
            location={location}
            onQueryChange={setQuery}
            onLocationChange={setLocation}
            onSubmit={() => openDirectory(category, subcategory)}
          />
        </div>

        <section className="directory-quick-actions" aria-label="Directory shortcuts">
          <button onClick={() => setTab('categories')}><Grid2X2 /><span><strong>Categories</strong><small>Browse business types</small></span><ChevronRight /></button>
          <button onClick={() => openDirectory('all', 'all', 'az')}><ListOrdered /><span><strong>A–Z Directory</strong><small>Browse every business</small></span><ChevronRight /></button>
          <button onClick={() => setApplicationOpen(true)}><Plus /><span><strong>Add a Business</strong><small>Submit a Black-owned business</small></span><ChevronRight /></button>
          <button onClick={() => { setTab('directory'); setToast('Open a business profile to claim it.') }}><ShieldCheck /><span><strong>Claim a Business</strong><small>Manage an existing listing</small></span><ChevronRight /></button>
        </section>

        <section className="directory-stats" aria-label="Directory totals">
          <div><strong>{businesses.length}</strong><span>Businesses</span></div>
          <div><strong>{categories.length}</strong><span>Categories</span></div>
          <div><strong>{cityCount}</strong><span>Cities</span></div>
        </section>

        <CategoryRail categories={categories} onSelectCategory={value => openDirectory(value, 'all')} onSeeAll={() => setTab('categories')} />

        <section className="section-block featured-businesses-section">
          <div className="section-title">
            <div><span>DIRECTORY PICKS</span><h2>Featured businesses</h2><p>Business profiles worth knowing.</p></div>
            <button onClick={() => openDirectory()}>Full directory <ChevronRight size={15} /></button>
          </div>
          <div className="horizontal-cards">
            {featuredRail.map(business => <BusinessCard compact key={business.directory_id} business={business} saved={savedIds.includes(business.directory_id)} onOpen={() => openBusiness(business)} onSave={() => toggleFavorite(business.directory_id)} />)}
          </div>
        </section>

        <section className="business-owner-banner">
          <div className="business-owner-banner-copy">
            <span>BUSINESS OWNERS</span>
            <h2>Make sure customers can find you.</h2>
            <p>Add your Black-owned business or claim an existing listing to keep its information accurate.</p>
          </div>
          <div className="business-owner-banner-actions">
            <button onClick={() => setApplicationOpen(true)}><Plus size={16} /> Add business</button>
            <button className="secondary" onClick={() => { setTab('directory'); setToast('Open your business profile and tap Claim this business.') }}><ShieldCheck size={16} /> Claim listing</button>
          </div>
        </section>
      </>}

      {tab === 'directory' && <section className="directory-page directory-results-page">
        <div className="directory-page-heading">
          <span><Search size={14} /> BUSINESS DIRECTORY</span>
          <h1>Find Black-owned businesses.</h1>
          <p>Search by business or service, then narrow by location and category.</p>
        </div>

        <DirectorySearchPanel
          compact
          query={query}
          location={location}
          onQueryChange={setQuery}
          onLocationChange={setLocation}
          onSubmit={() => undefined}
        />

        <CategoryFilterRail categories={categories} category={category} onCategoryChange={value => { setCategory(value); setSubcategory('all') }} />
        {category !== 'all' && <SubcategoryFilterRail subcategories={subcategories} subcategory={subcategory} onSubcategoryChange={setSubcategory} />}

        <div className="directory-result-tools">
          <div><strong>{pluralize(filtered.length, 'business', 'businesses')}</strong><small>{query || location || category !== 'all' ? ' matching your search' : ' in the directory'}</small></div>
          <div className="directory-sort" aria-label="Sort businesses">
            <button className={sort === 'recommended' ? 'active' : ''} onClick={() => setSort('recommended')}>Recommended</button>
            <button className={sort === 'az' ? 'active' : ''} onClick={() => setSort('az')}>A–Z</button>
          </div>
        </div>

        {loading ? <EmptyState icon={<Store />} title="Opening the directory" body="Loading Black-owned businesses." />
          : error ? <EmptyState icon={<Building2 />} title="Directory unavailable" body={error} />
          : filtered.length === 0 ? <EmptyState icon={<Search />} title="No businesses found" body="Try another business name, service, location, category, or subcategory." action={<button className="primary-action" onClick={resetDirectory}>Clear filters</button>} />
          : <div className="business-grid directory-business-grid">{filtered.map(business => <BusinessCard key={business.directory_id} business={business} saved={savedIds.includes(business.directory_id)} onOpen={() => openBusiness(business)} onSave={() => toggleFavorite(business.directory_id)} />)}</div>}
      </section>}

      {tab === 'categories' && <CategoryBrowser businesses={businesses} categories={categories} onBrowse={(nextCategory, nextSubcategory = 'all') => openDirectory(nextCategory, nextSubcategory)} />}

      {tab === 'saved' && <section className="directory-page saved-screen">
        <div className="directory-page-heading"><span><Bookmark size={14} /> SAVED BUSINESSES</span><h1>Your saved directory.</h1><p>Keep the businesses you want to find again in one place.</p></div>
        {!user ? <EmptyState icon={<Bookmark />} title="Sign in to save businesses" body="Create a personal list of Black-owned businesses you use or want to support." action={<button className="primary-action" onClick={() => setAuthOpen(true)}>Sign in <LogIn size={16} /></button>} />
          : savedBusinesses.length === 0 ? <EmptyState icon={<Heart />} title="No saved businesses yet" body="Save any business from the directory and it will appear here." action={<button className="primary-action" onClick={() => openDirectory()}>Browse directory <ArrowRight size={16} /></button>} />
          : <div className="business-grid directory-business-grid">{savedBusinesses.map(business => <BusinessCard key={business.directory_id} business={business} saved onOpen={() => openBusiness(business)} onSave={() => toggleFavorite(business.directory_id)} />)}</div>}
      </section>}

      {tab === 'account' && <section className="directory-page account-screen">
        <div className="account-card">
          <img src="/brand/black-pages-logo.webp" alt="" />
          <span>MY BLACK PAGES</span>
          <h1>{user ? user.user_metadata?.full_name || user.email : 'Directory account'}</h1>
          <p>{user ? 'Manage saved businesses and business listing actions.' : 'Sign in to save businesses and submit ownership claims.'}</p>
        </div>
        <div className="profile-actions directory-account-actions">
          {!user && <button onClick={() => setAuthOpen(true)}><span><LogIn /><strong>Sign in or create account</strong><small>Save and claim business listings</small></span><ChevronRight /></button>}
          <button onClick={() => setApplicationOpen(true)}><span><BriefcaseBusiness /><strong>Add a Black-owned business</strong><small>Submit a business for directory review</small></span><ChevronRight /></button>
          <button onClick={() => { setTab('directory'); setToast('Open the business profile you want to claim.') }}><span><ShieldCheck /><strong>Claim a business listing</strong><small>Request ownership of an existing profile</small></span><ChevronRight /></button>
          <button onClick={() => setTab('saved')}><span><Bookmark /><strong>Saved businesses</strong><small>{savedBusinesses.length} saved {savedBusinesses.length === 1 ? 'business' : 'businesses'}</small></span><ChevronRight /></button>
          {user && <button className="danger-action" onClick={async () => { await supabase.auth.signOut(); setTab('home'); setToast('Signed out.') }}><span><LogOut /><strong>Sign out</strong><small>{user.email}</small></span><ChevronRight /></button>}
        </div>
      </section>}
    </main>

    <nav className="bottom-nav directory-bottom-nav" aria-label="Primary navigation">
      {([
        ['home', Home, 'Home'],
        ['directory', Search, 'Directory'],
        ['categories', Grid2X2, 'Categories'],
        ['saved', Bookmark, 'Saved'],
        ['account', UserRound, 'Account'],
      ] as const).map(([id, Icon, label]) => <button key={id} className={tab === id ? 'active' : ''} onClick={() => setTab(id)}><Icon size={20} /><span>{label}</span></button>)}
    </nav>

    {selected && <div className="sheet-backdrop" onMouseDown={() => setSelected(null)}>
      <article className="business-sheet directory-business-sheet" onMouseDown={event => event.stopPropagation()}>
        <button className="sheet-close" onClick={() => setSelected(null)}><X /></button>
        <div className="sheet-image">{selected.image_url ? <img src={selected.image_url} alt="" /> : <div className="image-fallback"><Store /></div>}<div className="image-shade" /><StatusBadge business={selected} /></div>
        <div className="sheet-copy">
          <div className="card-meta"><span>{labelCategory(selected.category)}{selected.subcategory ? ` · ${labelSubcategory(selected.subcategory)}` : ''}</span><Rating business={selected} /></div>
          <h2>{selected.business_name}</h2>
          <p>{selected.short_description || `${labelCategory(selected.category)} in ${selected.city}.`}</p>
          <div className="sheet-location"><MapPin size={16} /><span><strong>{selected.neighborhood || selected.city}</strong><small>{selected.address || `${selected.city}${selected.state ? `, ${selected.state}` : ''}`}</small></span></div>
          <div className="quick-actions directory-quick-contact">
            {selected.phone && <a href={`tel:${selected.phone}`}><Phone /><span>Call</span></a>}
            <a href={mapsUrl(selected)} target="_blank" rel="noreferrer"><Navigation /><span>Directions</span></a>
            {selected.website_url && <a href={selected.website_url} target="_blank" rel="noreferrer"><Globe2 /><span>Website</span></a>}
            {selected.instagram_handle && <a href={`https://instagram.com/${selected.instagram_handle.replace('@', '')}`} target="_blank" rel="noreferrer"><Camera /><span>Instagram</span></a>}
          </div>
          <button className={`sheet-save ${savedIds.includes(selected.directory_id) ? 'saved' : ''}`} onClick={() => toggleFavorite(selected.directory_id)}><Bookmark fill={savedIds.includes(selected.directory_id) ? 'currentColor' : 'none'} /> {savedIds.includes(selected.directory_id) ? 'Saved business' : 'Save business'}</button>
          <button className="claim-button" onClick={() => { setClaimName(user?.user_metadata?.full_name || ''); setClaimEmail(user?.email || ''); setClaimOpen(true) }}><ShieldCheck /> Claim this business listing <ChevronRight /></button>
          <p className="profile-note">Business information comes from directory research and owner submissions. Confirm details directly with the business.</p>
        </div>
      </article>
    </div>}

    {authOpen && <div className="modal-backdrop" onMouseDown={() => setAuthOpen(false)}><form className="auth-modal" onSubmit={authenticate} onMouseDown={event => event.stopPropagation()}><button type="button" className="modal-close" onClick={() => setAuthOpen(false)}><X /></button><AppMark /><span className="eyebrow">MY BLACK PAGES</span><h2>{authMode === 'signin' ? 'Sign in.' : 'Create an account.'}</h2><p>Save businesses and claim business listings.</p><div className="segmented"><button type="button" className={authMode === 'signin' ? 'active' : ''} onClick={() => setAuthMode('signin')}>Sign in</button><button type="button" className={authMode === 'signup' ? 'active' : ''} onClick={() => setAuthMode('signup')}>Create account</button></div>{authMode === 'signup' && <label>Full name<input required value={authName} onChange={event => setAuthName(event.target.value)} /></label>}<label>Email<input required type="email" value={authEmail} onChange={event => setAuthEmail(event.target.value)} /></label><label>Password<input required minLength={8} type="password" value={authPassword} onChange={event => setAuthPassword(event.target.value)} /></label>{authError && <div className="form-error">{authError}</div>}<button className="primary-action" disabled={authBusy}>{authBusy ? 'Connecting…' : authMode === 'signin' ? 'Sign in' : 'Create account'} <ArrowRight size={16} /></button></form></div>}

    {applicationOpen && <div className="modal-backdrop" onMouseDown={() => setApplicationOpen(false)}><form className="application-modal" onSubmit={submitApplication} onMouseDown={event => event.stopPropagation()}><button type="button" className="modal-close" onClick={() => setApplicationOpen(false)}><X /></button>{applicationSuccess ? <div className="success-state"><div className="success-check"><Check /></div><span>BUSINESS RECEIVED</span><h2>Your listing is in review.</h2><p>It will appear in the directory after its Black ownership and business details are reviewed.</p><button type="button" className="primary-action" onClick={() => { setApplicationSuccess(false); setApplicationOpen(false) }}>Done</button></div> : <><span className="eyebrow">ADD A BUSINESS</span><h2>List a Black-owned business.</h2><p>Submit accurate public business information for directory review.</p><div className="form-grid"><label>Business name<input required value={application.businessName} onChange={event => setApplication({ ...application, businessName: event.target.value })} /></label><label>Owner/contact name<input required value={application.ownerName} onChange={event => setApplication({ ...application, ownerName: event.target.value })} /></label><label>Email<input required type="email" value={application.contactEmail} onChange={event => setApplication({ ...application, contactEmail: event.target.value })} /></label><label>Phone<input value={application.contactPhone} onChange={event => setApplication({ ...application, contactPhone: event.target.value })} /></label><label>Category<select required value={application.category} onChange={event => setApplication({ ...application, category: event.target.value })}><option value="">Choose category</option>{listingCategories.map(item => <option key={item}>{item}</option>)}</select></label><label>City<input required value={application.city} onChange={event => setApplication({ ...application, city: event.target.value })} /></label><label>State<input required maxLength={2} value={application.state} onChange={event => setApplication({ ...application, state: event.target.value.toUpperCase() })} /></label><label>Website<input type="url" placeholder="https://" value={application.websiteUrl} onChange={event => setApplication({ ...application, websiteUrl: event.target.value })} /></label><label>Instagram<input placeholder="@handle" value={application.instagramHandle} onChange={event => setApplication({ ...application, instagramHandle: event.target.value })} /></label><label className="wide">Business description<textarea required maxLength={1200} value={application.description} onChange={event => setApplication({ ...application, description: event.target.value })} /></label><label className="certify wide"><input required type="checkbox" checked={application.ownershipCertification} onChange={event => setApplication({ ...application, ownershipCertification: event.target.checked })} /><span>I certify that this business is Black-owned and that I am authorized to submit it.</span></label></div>{applicationError && <div className="form-error">{applicationError}</div>}<button className="primary-action" disabled={applicationBusy}>{applicationBusy ? 'Submitting…' : 'Submit business'} <ArrowRight size={16} /></button></>}</form></div>}

    {claimOpen && selected && <div className="modal-backdrop" onMouseDown={() => setClaimOpen(false)}><form className="auth-modal" onSubmit={submitClaim} onMouseDown={event => event.stopPropagation()}><button type="button" className="modal-close" onClick={() => setClaimOpen(false)}><X /></button>{claimSuccess ? <div className="success-state"><div className="success-check"><Check /></div><span>CLAIM RECEIVED</span><h2>We’ll verify your connection.</h2><p>The public listing will not change until your claim is reviewed.</p><button type="button" className="primary-action" onClick={() => { setClaimSuccess(false); setClaimOpen(false) }}>Done</button></div> : <><ShieldCheck className="modal-icon" /><span className="eyebrow">CLAIM BUSINESS</span><h2>{selected.business_name}</h2><p>Tell us your role at this business.</p><label>Your name<input required value={claimName} onChange={event => setClaimName(event.target.value)} /></label><label>Email<input required type="email" value={claimEmail} onChange={event => setClaimEmail(event.target.value)} /></label><label>Role at business<select value={claimRole} onChange={event => setClaimRole(event.target.value)}><option>Owner</option><option>Co-owner</option><option>Manager</option><option>Authorized representative</option></select></label><button className="primary-action" disabled={claimBusy}>{claimBusy ? 'Submitting…' : 'Submit claim'} <ArrowRight size={16} /></button></>}</form></div>}

    {toast && <div className="toast">{toast}</div>}
    <BuildInfoBadge />
  </div>
}
