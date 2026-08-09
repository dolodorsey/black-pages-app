import { useEffect, useState } from 'react'

function mapUrl(latitude: number, longitude: number) {
  const lngSpan = 0.16
  const latSpan = 0.12
  const left = longitude - lngSpan
  const right = longitude + lngSpan
  const bottom = latitude - latSpan
  const top = latitude + latSpan
  return `https://www.openstreetmap.org/export/embed.html?bbox=${encodeURIComponent(`${left},${bottom},${right},${top}`)}&layer=mapnik&marker=${encodeURIComponent(`${latitude},${longitude}`)}`
}

export default function LocationInteractionHost() {
  const [message, setMessage] = useState('')
  const [error, setError] = useState(false)

  useEffect(() => {
    if (!message) return
    const timer = window.setTimeout(() => setMessage(''), 3200)
    return () => window.clearTimeout(timer)
  }, [message])

  useEffect(() => {
    const requestLocation = () => {
      if (!navigator.geolocation) {
        setError(true)
        setMessage('Location services are not available on this device.')
        return
      }
      setError(false)
      setMessage('Finding your location…')
      navigator.geolocation.getCurrentPosition(
        position => {
          const iframe = document.querySelector<HTMLIFrameElement>('.map-canvas iframe')
          if (!iframe) {
            setError(true)
            setMessage('Open the Map tab and try again.')
            return
          }
          iframe.src = mapUrl(position.coords.latitude, position.coords.longitude)
          iframe.title = 'Black Pages businesses near my location'
          setError(false)
          setMessage('Map centered on your current location.')
        },
        locationError => {
          setError(true)
          setMessage(locationError.code === 1
            ? 'Location permission is blocked. Enable it in your browser or phone settings.'
            : 'Your location could not be determined. Try again in a moment.')
        },
        { enableHighAccuracy: true, timeout: 12000, maximumAge: 60000 },
      )
    }

    const handler = (event: MouseEvent) => {
      const target = event.target instanceof Element ? event.target : null
      const button = target?.closest('button') as HTMLButtonElement | null
      if (!button) return
      if (button.matches('.recenter') || button.getAttribute('aria-label') === 'Use my location') {
        if (button.matches('.recenter')) {
          event.preventDefault()
          event.stopImmediatePropagation()
        }
        window.setTimeout(requestLocation, button.getAttribute('aria-label') === 'Use my location' ? 75 : 0)
      }
    }

    document.addEventListener('click', handler, true)
    return () => document.removeEventListener('click', handler, true)
  }, [])

  if (!message) return null
  return <div role="status" aria-live="polite" style={{position:'fixed',left:'50%',bottom:88,transform:'translateX(-50%)',zIndex:5000,width:'min(360px,calc(100% - 32px))',padding:'11px 14px',borderRadius:14,background:error?'#481818':'#121d18',color:'#fff',boxShadow:'0 14px 45px rgba(0,0,0,.28)',fontSize:12,fontWeight:700,textAlign:'center'}}>{message}</div>
}
