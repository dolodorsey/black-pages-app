import { Component, type ErrorInfo, type ReactNode } from 'react'
import { Building2 } from 'lucide-react'
import { EmptyState } from './primitives'

type ErrorBoundaryProps = {
  children: ReactNode
}

type ErrorBoundaryState = {
  error: Error | null
}

/**
 * Catches render-time failures — most importantly the environment validation
 * error thrown when a required VITE_* variable is missing or malformed — and
 * renders an explanatory screen instead of a blank page.
 */
export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { error: null }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('THE BLACK PAGES failed to render.', error, info.componentStack)
  }

  render() {
    const { error } = this.state
    if (!error) return this.props.children
    return <div className="app-shell">
      <main className="app-content">
        <EmptyState
          icon={<Building2 />}
          title="THE BLACK PAGES could not start"
          body={error.message}
          action={<button className="primary-action" onClick={() => window.location.reload()}>Reload</button>}
        />
      </main>
    </div>
  }
}
