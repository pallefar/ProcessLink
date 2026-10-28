/**
 * Host adapter boundary.
 *
 * The standalone build uses in-memory sandbox data. In Flightdeck the same
 * pages call these functions, which are the only place that knows about the
 * host's API, session and permission model. Keeping the seam here means the
 * domain rules and pages never import host code.
 */
import type { Answer, Initiative, Opportunity, PrivacyPolicy, Process } from '../domain/types'

export interface HostSession {
  workspaceId: string
  user: string
  roles: string[]
  /** Region pin from the workspace policy. */
  region: string
  /** Group threshold owned by the data owner / works council. */
  minimumGroupSize: number
  /** Feature flags resolved by the host, e.g. processlink.graphrag. */
  flags: Record<string, boolean>
}

export interface ProcessLinkSource {
  processes(): Promise<Process[]>
  opportunities(): Promise<Opportunity[]>
  initiatives(): Promise<Initiative[]>
  promote(opportunityId: string): Promise<Initiative>
  commit(initiativeId: string): Promise<Initiative>
  validate(initiativeId: string, validator: string, evidence: string): Promise<Initiative>
  ask(question: string, session: HostSession): Promise<Answer>
}

/**
 * Builds the policy from the host session. The threshold is NOT a user
 * preference: it comes from the workspace policy the host resolves.
 */
export function policyFromSession(session: HostSession): PrivacyPolicy {
  return {
    minimumGroupSize: session.minimumGroupSize,
    retentionDays: 400,
    provider: session.flags.hostedAI ? 'Anthropic Claude · EU' : 'Local (on device)',
    region: session.region,
    purpose: 'processImprovement',
    dataOwner: 'CI Manager (role)',
  }
}

/** Every call must carry the session; the server re-checks the guard. */
export function requireRole(session: HostSession, role: string): void {
  if (!session.roles.includes(role) && !session.roles.includes('admin')) {
    throw new Error(`Role ${role} is required for this action`)
  }
}

/** Placeholder endpoints; wire these to `/api/apps/processlink/*` on the host. */
export const ROUTES = {
  processes: '/api/apps/processlink/processes',
  opportunities: '/api/apps/processlink/opportunities',
  initiatives: '/api/apps/processlink/initiatives',
  sync: '/api/apps/processlink/sync',
  ask: '/api/apps/processlink/ask',
  kg: '/api/apps/processlink/kg',
} as const
