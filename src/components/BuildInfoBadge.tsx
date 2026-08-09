import { getBuildInfo } from '../lib/build-info'

/**
 * Hidden diagnostics element: the deployed commit is inspectable in the DOM
 * (and via `window.__BUILD_INFO__` / `/build-info.json`) without changing the
 * rendered design. It exposes no secrets.
 */
export function BuildInfoBadge() {
  const { commit, builtAt } = getBuildInfo()
  return <div id="build-info" hidden data-commit={commit} data-built-at={builtAt}>
    {commit.slice(0, 12)}
  </div>
}
