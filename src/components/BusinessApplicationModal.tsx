import { type FormEvent, useMemo, useState } from 'react'
import { ArrowRight, Building2, Check, Clock3, Globe2, Image, MapPin, ShieldCheck, X } from 'lucide-react'
import { subcategoriesFor, type TaxonomyCategory, type TaxonomySubcategory } from '../services/taxonomy.ts'

const initialForm = {
  businessName: '', ownerName: '', contactEmail: '', contactPhone: '',
  businessEmail: '', businessPhone: '', category: '', subcategory: '',
  addressLine1: '', addressLine2: '', neighborhood: '', city: '', state: '', postalCode: '',
  serviceArea: '', serviceRadiusMiles: '25', servesCustomersAtLocation: true,
  websiteUrl: '', instagramHandle: '', facebookUrl: '', linkedinUrl: '', tiktokUrl: '',
  hoursSummary: '', description: '', specialtiesText: '', photoUrlsText: '', ownershipProofUrlsText: '',
  ownershipCertification: false,
}

function listFromText(value: string) {
  return value.split(/[\n,]+/).map(item => item.trim()).filter(Boolean)
}

export function BusinessApplicationModal({ open, onClose, supabaseUrl, categories, subcategories, onSubmitted }: {
  open: boolean
  onClose: () => void
  supabaseUrl: string
  categories: readonly TaxonomyCategory[]
  subcategories: readonly TaxonomySubcategory[]
  onSubmitted: () => void
}) {
  const [form, setForm] = useState(initialForm)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState(false)
  const availableSubcategories = useMemo(() => subcategoriesFor(subcategories, form.category), [subcategories, form.category])

  if (!open) return null

  function close() {
    setError('')
    setSuccess(false)
    onClose()
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (busy) return
    setBusy(true)
    setError('')
    try {
      const response = await fetch(`${supabaseUrl}/functions/v1/black-pages-application`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...form,
          specialties: listFromText(form.specialtiesText),
          photoUrls: listFromText(form.photoUrlsText),
          ownershipProofUrls: listFromText(form.ownershipProofUrlsText),
          serviceRadiusMiles: Number(form.serviceRadiusMiles || 0),
        }),
      })
      const body = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(body.error || 'Business could not be submitted.')
      setSuccess(true)
      setForm(initialForm)
      onSubmitted()
    } catch (submissionError) {
      setError(submissionError instanceof Error ? submissionError.message : 'Business could not be submitted.')
    } finally {
      setBusy(false)
    }
  }

  return <div className="modal-backdrop" onMouseDown={close}>
    <form className="application-modal directory-application-modal" onSubmit={submit} onMouseDown={event => event.stopPropagation()}>
      <button type="button" className="modal-close" onClick={close}><X /></button>
      {success ? <div className="success-state">
        <div className="success-check"><Check /></div>
        <span>BUSINESS RECEIVED</span>
        <h2>Your listing is in review.</h2>
        <p>We received the business profile, location details, category, and ownership evidence. It will publish after review.</p>
        <button type="button" className="primary-action" onClick={close}>Done</button>
      </div> : <>
        <span className="eyebrow">ADD A BLACK-OWNED BUSINESS</span>
        <h2>Build a complete directory listing.</h2>
        <p>Give customers the same practical information they expect from a modern business directory.</p>

        <section className="application-section">
          <div className="application-section-title"><Building2 /><div><strong>Business</strong><small>Public identity and classification</small></div></div>
          <div className="form-grid">
            <label>Business name<input required value={form.businessName} onChange={event => setForm({ ...form, businessName: event.target.value })} /></label>
            <label>Category<select required value={form.category} onChange={event => setForm({ ...form, category: event.target.value, subcategory: '' })}><option value="">Choose category</option>{categories.map(item => <option key={item.slug} value={item.slug}>{item.name}</option>)}</select></label>
            <label>Subcategory<select required disabled={!form.category} value={form.subcategory} onChange={event => setForm({ ...form, subcategory: event.target.value })}><option value="">Choose subcategory</option>{availableSubcategories.map(item => <option key={item.slug} value={item.slug}>{item.name}</option>)}</select></label>
            <label>Public business phone<input type="tel" value={form.businessPhone} onChange={event => setForm({ ...form, businessPhone: event.target.value })} /></label>
            <label>Public business email<input type="email" value={form.businessEmail} onChange={event => setForm({ ...form, businessEmail: event.target.value })} /></label>
            <label className="wide">Specialties / services<input placeholder="e.g. Commercial plumbing, emergency repair, water heaters" value={form.specialtiesText} onChange={event => setForm({ ...form, specialtiesText: event.target.value })} /></label>
          </div>
        </section>

        <section className="application-section">
          <div className="application-section-title"><MapPin /><div><strong>Location & service area</strong><small>Power city, neighborhood, ZIP and near-me search</small></div></div>
          <label className="certify location-toggle"><input type="checkbox" checked={form.servesCustomersAtLocation} onChange={event => setForm({ ...form, servesCustomersAtLocation: event.target.checked })} /><span>Customers can visit this business location.</span></label>
          <div className="form-grid">
            {form.servesCustomersAtLocation && <><label>Street address<input required value={form.addressLine1} onChange={event => setForm({ ...form, addressLine1: event.target.value })} /></label><label>Suite / unit<input value={form.addressLine2} onChange={event => setForm({ ...form, addressLine2: event.target.value })} /></label></>}
            <label>Neighborhood<input placeholder="Optional" value={form.neighborhood} onChange={event => setForm({ ...form, neighborhood: event.target.value })} /></label>
            <label>City<input required value={form.city} onChange={event => setForm({ ...form, city: event.target.value })} /></label>
            <label>State<input required maxLength={2} placeholder="GA" value={form.state} onChange={event => setForm({ ...form, state: event.target.value.toUpperCase() })} /></label>
            <label>ZIP code<input required inputMode="numeric" placeholder="30305" value={form.postalCode} onChange={event => setForm({ ...form, postalCode: event.target.value })} /></label>
            {!form.servesCustomersAtLocation && <label className="wide">Service area<input required placeholder="e.g. Metro Atlanta, Fulton + DeKalb Counties" value={form.serviceArea} onChange={event => setForm({ ...form, serviceArea: event.target.value })} /></label>}
            <label>Service radius (miles)<input type="number" min="0" max="500" value={form.serviceRadiusMiles} onChange={event => setForm({ ...form, serviceRadiusMiles: event.target.value })} /></label>
          </div>
        </section>

        <section className="application-section">
          <div className="application-section-title"><Globe2 /><div><strong>Contact & web</strong><small>Direct ways for customers to reach the business</small></div></div>
          <div className="form-grid">
            <label>Website<input type="url" placeholder="https://" value={form.websiteUrl} onChange={event => setForm({ ...form, websiteUrl: event.target.value })} /></label>
            <label>Instagram<input placeholder="@handle" value={form.instagramHandle} onChange={event => setForm({ ...form, instagramHandle: event.target.value })} /></label>
            <label>Facebook URL<input type="url" placeholder="https://" value={form.facebookUrl} onChange={event => setForm({ ...form, facebookUrl: event.target.value })} /></label>
            <label>LinkedIn URL<input type="url" placeholder="https://" value={form.linkedinUrl} onChange={event => setForm({ ...form, linkedinUrl: event.target.value })} /></label>
            <label>TikTok URL<input type="url" placeholder="https://" value={form.tiktokUrl} onChange={event => setForm({ ...form, tiktokUrl: event.target.value })} /></label>
          </div>
        </section>

        <section className="application-section">
          <div className="application-section-title"><Clock3 /><div><strong>Directory details</strong><small>Hours, description and photos</small></div></div>
          <div className="form-grid">
            <label className="wide">Business hours<textarea placeholder="Mon–Fri 9am–6pm; Sat 10am–3pm; Sun closed" value={form.hoursSummary} onChange={event => setForm({ ...form, hoursSummary: event.target.value })} /></label>
            <label className="wide">Business description<textarea required maxLength={1600} value={form.description} onChange={event => setForm({ ...form, description: event.target.value })} /></label>
            <label className="wide"><span className="label-with-icon"><Image size={13} /> Photo URLs</span><textarea placeholder="One image URL per line (up to 8)" value={form.photoUrlsText} onChange={event => setForm({ ...form, photoUrlsText: event.target.value })} /></label>
          </div>
        </section>

        <section className="application-section ownership-section">
          <div className="application-section-title"><ShieldCheck /><div><strong>Ownership verification</strong><small>Only Black-owned businesses belong in this directory</small></div></div>
          <div className="form-grid">
            <label>Submitter / owner name<input required value={form.ownerName} onChange={event => setForm({ ...form, ownerName: event.target.value })} /></label>
            <label>Private contact email<input required type="email" value={form.contactEmail} onChange={event => setForm({ ...form, contactEmail: event.target.value })} /></label>
            <label>Private contact phone<input type="tel" value={form.contactPhone} onChange={event => setForm({ ...form, contactPhone: event.target.value })} /></label>
            <label className="wide">Ownership proof link(s)<textarea required placeholder="Public owner bio, business About page, certification, filing, press profile, etc. One URL per line." value={form.ownershipProofUrlsText} onChange={event => setForm({ ...form, ownershipProofUrlsText: event.target.value })} /></label>
            <label className="certify wide"><input required type="checkbox" checked={form.ownershipCertification} onChange={event => setForm({ ...form, ownershipCertification: event.target.checked })} /><span>I certify that this business is Black-owned and that I am authorized to submit its information.</span></label>
          </div>
        </section>

        {error && <div className="form-error">{error}</div>}
        <button className="primary-action application-submit" disabled={busy}>{busy ? 'Submitting…' : 'Submit business for review'} <ArrowRight size={16} /></button>
      </>}
    </form>
  </div>
}
