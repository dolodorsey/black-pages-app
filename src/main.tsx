import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import LocationInteractionHost from './LocationInteractionHost'
import ReviewInteractionHost from './ReviewInteractionHost'
import { ErrorBoundary } from './components/ErrorBoundary'
import { publishBuildInfo } from './lib/build-info'
import './styles.css'
import './current-media.css'
import './categories.css'

publishBuildInfo()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <LocationInteractionHost/>
      <ReviewInteractionHost/>
      <App/>
    </ErrorBoundary>
  </StrictMode>,
)
