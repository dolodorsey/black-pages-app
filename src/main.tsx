import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import CoverageCommandCenterHost from './CoverageCommandCenterHost'
import LocationInteractionHost from './LocationInteractionHost'
import ReviewInteractionHost from './ReviewInteractionHost'
import { ErrorBoundary } from './components/ErrorBoundary'
import { publishBuildInfo } from './lib/build-info'
import './styles.css'
import './current-media.css'
import './categories.css'
import './directory-ui.css'
import './location-intelligence.css'
import './p0-mobile-fixes.css'

publishBuildInfo()

const coverageMode = new URLSearchParams(window.location.search).get('coverage') === '1'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      {coverageMode ? <CoverageCommandCenterHost /> : <>
        <LocationInteractionHost/>
        <ReviewInteractionHost/>
        <App/>
      </>}
    </ErrorBoundary>
  </StrictMode>,
)
