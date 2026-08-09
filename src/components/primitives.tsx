import { BadgeCheck, ShieldCheck, Star } from 'lucide-react'
import type { ReactNode } from 'react'
import type { DirectoryBusiness } from '../services/directory'

export function AppMark() {
  return <div className="app-mark"><span>TBP</span></div>
}

export function StatusBadge({ business }: { business: DirectoryBusiness }) {
  return business.owner_verified
    ? <span className="status-badge owner"><ShieldCheck size={12} /> Owner verified</span>
    : <span className="status-badge"><BadgeCheck size={12} /> Black-owned profile</span>
}

export function Rating({ business }: { business: DirectoryBusiness }) {
  if (!business.rating) return <span className="rating quiet">New profile</span>
  return <span className="rating"><Star size={12} fill="currentColor" /> {Number(business.rating).toFixed(1)}{business.review_count ? <small>({business.review_count})</small> : null}</span>
}

export function EmptyState({ icon, title, body, action }: { icon: ReactNode; title: string; body: string; action?: ReactNode }) {
  return <div className="empty-state">{icon}<h3>{title}</h3><p>{body}</p>{action}</div>
}
