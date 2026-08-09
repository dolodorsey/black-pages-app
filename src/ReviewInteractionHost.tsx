import { FormEvent, useEffect, useMemo, useState } from 'react'
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://dzlmtvodpyhetvektfuo.supabase.co'
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
const supabase = supabaseKey ? createClient(supabaseUrl, supabaseKey) : null

type ReviewTarget = {
  directory_id: string
  business_name: string
  city: string
  state: string
  address: string | null
}

type ExistingReview = {
  id: string
  rating: number
  review_text: string | null
  status: string
}

const text = (node: Element | null | undefined) => String(node?.textContent || '').replace(/\s+/g, ' ').trim()

async function resolveBusinessFromSheet(sheet: Element): Promise<ReviewTarget | null> {
  if (!supabase) return null
  const businessName = text(sheet.querySelector('h2'))
  if (!businessName) return null
  const locationText = text(sheet.querySelector('.sheet-location'))
  const { data, error } = await supabase
    .from('black_pages_directory')
    .select('directory_id,business_name,city,state,address')
    .eq('business_name', businessName)
    .limit(10)
  if (error || !data?.length) return null
  if (data.length === 1) return data[0] as ReviewTarget
  const normalized = locationText.toLowerCase()
  return (data.find(row => row.address && normalized.includes(String(row.address).toLowerCase()))
    || data.find(row => normalized.includes(String(row.city).toLowerCase()))
    || data[0]) as ReviewTarget
}

export default function ReviewInteractionHost() {
  const [target, setTarget] = useState<ReviewTarget | null>(null)
  const [existing, setExisting] = useState<ExistingReview | null>(null)
  const [rating, setRating] = useState(5)
  const [reviewText, setReviewText] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [notice, setNotice] = useState('')

  useEffect(() => {
    let injectedSheet: Element | null = null
    let button: HTMLButtonElement | null = null
    let disposed = false

    const removeButton = () => {
      button?.remove()
      button = null
      injectedSheet = null
    }

    const inject = () => {
      const sheet = document.querySelector('.business-sheet')
      if (!sheet) { removeButton(); return }
      if (sheet === injectedSheet && sheet.querySelector('[data-black-pages-review-button="true"]')) return
      removeButton()
      const claimButton = sheet.querySelector('.claim-button')
      const copy = sheet.querySelector('.sheet-copy')
      if (!copy) return
      button = document.createElement('button')
      button.type = 'button'
      button.dataset.blackPagesReviewButton = 'true'
      button.className = 'claim-button'
      button.style.marginTop = '10px'
      button.innerHTML = '<span aria-hidden="true">★</span> Write a review <span aria-hidden="true">›</span>'
      button.addEventListener('click', async event => {
        event.preventDefault()
        event.stopPropagation()
        setError(''); setSuccess(''); setNotice('')
        if (!supabase) { setNotice('Review service is not configured for this release.'); return }
        const { data: { session } } = await supabase.auth.getSession()
        if (!session?.user) {
          setNotice('Sign in to submit a review. Opening account access…')
          const authButton = document.querySelector('.avatar-button')
          if (authButton instanceof HTMLButtonElement) authButton.click()
          return
        }
        const resolved = await resolveBusinessFromSheet(sheet)
        if (!resolved) { setNotice('This business profile could not be resolved for review.'); return }
        const { data: prior, error: priorError } = await supabase
          .from('black_pages_reviews')
          .select('id,rating,review_text,status')
          .eq('directory_id', resolved.directory_id)
          .eq('reviewer_auth_id', session.user.id)
          .maybeSingle()
        if (priorError) { setNotice(priorError.message); return }
        const previous = prior as ExistingReview | null
        setTarget(resolved)
        setExisting(previous)
        setRating(previous?.rating || 5)
        setReviewText(previous?.review_text || '')
        if (previous?.status === 'approved') setNotice('Your review is already approved and public. Approved reviews are locked from direct editing.')
        if (previous?.status === 'rejected') setNotice('Your previous review is no longer editable. Contact support if you need it reconsidered.')
      })
      if (claimButton) copy.insertBefore(button, claimButton)
      else copy.appendChild(button)
      injectedSheet = sheet
    }

    const observer = new MutationObserver(() => { if (!disposed) inject() })
    observer.observe(document.body, { childList: true, subtree: true })
    inject()
    return () => { disposed = true; observer.disconnect(); removeButton() }
  }, [])

  useEffect(() => {
    if (!notice) return
    const timer = window.setTimeout(() => setNotice(''), 3600)
    return () => window.clearTimeout(timer)
  }, [notice])

  const editable = !existing || existing.status === 'pending'
  const remaining = useMemo(() => Math.max(0, 1200 - reviewText.length), [reviewText])

  async function submitReview(event: FormEvent) {
    event.preventDefault()
    if (!supabase || !target || busy || !editable) return
    setBusy(true); setError(''); setSuccess('')
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Sign in again to submit your review.')
      const cleaned = reviewText.trim()
      if (rating < 1 || rating > 5) throw new Error('Choose a rating from 1 to 5 stars.')
      if (cleaned.length < 10) throw new Error('Write at least 10 characters about your experience.')
      if (cleaned.length > 1200) throw new Error('Review text must be 1,200 characters or fewer.')

      if (existing?.id) {
        const { error: updateError } = await supabase
          .from('black_pages_reviews')
          .update({ rating, review_text: cleaned, updated_at: new Date().toISOString() })
          .eq('id', existing.id)
          .eq('reviewer_auth_id', user.id)
          .eq('status', 'pending')
        if (updateError) throw updateError
        setExisting({ ...existing, rating, review_text: cleaned })
      } else {
        const { data, error: insertError } = await supabase
          .from('black_pages_reviews')
          .insert({ directory_id: target.directory_id, reviewer_auth_id: user.id, rating, review_text: cleaned, status: 'pending' })
          .select('id,rating,review_text,status')
          .single()
        if (insertError) throw insertError
        setExisting(data as ExistingReview)
      }
      setSuccess('Review submitted for moderation. It will not affect the public rating until approved.')
    } catch (submissionError) {
      setError(submissionError instanceof Error ? submissionError.message : 'Review could not be submitted.')
    } finally {
      setBusy(false)
    }
  }

  return <>
    {notice && !target ? <div role="status" style={{position:'fixed',left:'50%',bottom:88,transform:'translateX(-50%)',zIndex:6500,width:'min(390px,calc(100% - 30px))',padding:'11px 14px',borderRadius:14,background:'#171b22',color:'#fff',boxShadow:'0 16px 50px rgba(0,0,0,.3)',fontSize:12,fontWeight:700,textAlign:'center'}}>{notice}</div> : null}
    {target ? <div role="dialog" aria-modal="true" aria-label={`Review ${target.business_name}`} onMouseDown={() => setTarget(null)} style={{position:'fixed',inset:0,zIndex:7200,background:'rgba(8,10,14,.72)',backdropFilter:'blur(12px)',display:'grid',placeItems:'end center',padding:12}}>
      <form onSubmit={submitReview} onMouseDown={event => event.stopPropagation()} style={{width:'min(520px,100%)',maxHeight:'82dvh',overflowY:'auto',borderRadius:24,background:'#fff',color:'#151820',padding:18,boxShadow:'0 28px 100px rgba(0,0,0,.42)'}}>
        <header style={{display:'flex',justifyContent:'space-between',gap:12,alignItems:'flex-start'}}><div><small style={{fontSize:9,fontWeight:900,letterSpacing:'.14em',color:'#7c5a27'}}>THE BLACK PAGES · COMMUNITY REVIEW</small><h2 style={{margin:'5px 0 3px',fontSize:23}}>{target.business_name}</h2><p style={{margin:0,fontSize:11,color:'#68707d'}}>{target.city}, {target.state}</p></div><button type="button" onClick={() => setTarget(null)} style={{border:0,borderRadius:12,width:36,height:36,background:'#eef1f5',fontSize:20,cursor:'pointer'}}>×</button></header>
        {notice ? <div style={{marginTop:13,padding:11,borderRadius:12,background:'#fff8e7',color:'#785a15',fontSize:11,lineHeight:1.45}}>{notice}</div> : null}
        {error ? <div style={{marginTop:13,padding:11,borderRadius:12,background:'#fff0f0',color:'#b42318',fontSize:11}}>{error}</div> : null}
        {success ? <div style={{marginTop:13,padding:11,borderRadius:12,background:'#edf9f1',color:'#18794e',fontSize:11,lineHeight:1.45}}>{success}</div> : null}
        <div style={{marginTop:16}}><span style={{display:'block',fontSize:10,fontWeight:900,letterSpacing:'.09em',marginBottom:8}}>YOUR RATING</span><div style={{display:'flex',gap:6}}>{[1,2,3,4,5].map(value => <button type="button" key={value} disabled={!editable} onClick={() => setRating(value)} aria-label={`${value} star${value === 1 ? '' : 's'}`} style={{border:0,background:'transparent',padding:2,fontSize:30,color:value <= rating ? '#b6812e' : '#cfd4dc',cursor:editable?'pointer':'default'}}>★</button>)}</div></div>
        <label style={{display:'block',marginTop:14,fontSize:10,fontWeight:900,letterSpacing:'.09em'}}>YOUR EXPERIENCE<textarea disabled={!editable} value={reviewText} onChange={event => setReviewText(event.target.value.slice(0,1200))} placeholder="What should other people know about your experience with this business?" style={{display:'block',width:'100%',minHeight:130,resize:'vertical',marginTop:8,padding:12,border:'1px solid #dce1e8',borderRadius:14,font:'inherit',fontSize:13,lineHeight:1.5,boxSizing:'border-box'}} /></label>
        <div style={{display:'flex',justifyContent:'space-between',gap:10,marginTop:6,fontSize:9,color:'#818895'}}><span>{existing ? `Status: ${existing.status}` : 'New review'}</span><span>{remaining} characters left</span></div>
        {editable ? <button disabled={busy} style={{width:'100%',marginTop:15,border:0,borderRadius:14,padding:'14px 16px',background:'#17191e',color:'#fff',fontSize:11,fontWeight:900,letterSpacing:'.07em',cursor:busy?'wait':'pointer'}}>{busy ? 'Submitting…' : existing ? 'Update pending review' : 'Submit for moderation'}</button> : null}
        <p style={{margin:'12px 0 0',fontSize:10,lineHeight:1.5,color:'#7d8490'}}>Reviews enter moderation first. They do not change the public business rating or review count until approved.</p>
      </form>
    </div> : null}
  </>
}
