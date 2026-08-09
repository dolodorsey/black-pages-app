import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import LocationInteractionHost from './LocationInteractionHost'
import ReviewInteractionHost from './ReviewInteractionHost'
import './styles.css'
import './current-media.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <LocationInteractionHost/>
    <ReviewInteractionHost/>
    <App/>
  </StrictMode>,
)
