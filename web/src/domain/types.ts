export type WasteType =
  | 'waiting'
  | 'rework'
  | 'overProcessing'
  | 'handoffs'
  | 'contextSwitching'
  | 'defects'
  | 'unusedTalent'
  | 'backlog'

export type Route = 'eliminate' | 'simplify' | 'standardize' | 'automate' | 'leave'

export type MethodKey =
  | '5s'
  | 'vsm'
  | 'standardWork'
  | 'smed'
  | 'kaizen'
  | 'a3'
  | 'hoshin'
  | 'dailyManagement'
  | 'tpm'
  | 'errorProofing'

export type SavingsStage = 'estimated' | 'committed' | 'validated'

export type Classification = 'public' | 'internal' | 'confidential' | 'restricted'

export type Destination = 'localView' | 'aiGateway' | 'knowledgeGraph' | 'export' | 'deck'

export type Purpose = 'processImprovement' | 'reporting' | 'qualityReview' | 'individualPerformance'

export type MeetingKind = 'dailyHuddle' | 'kaizen' | 'a3Review' | 'leadership' | 'workshop' | 'oneToOne'
export type BlockKind = 'heading' | 'text' | 'bullet' | 'checklist' | 'decision' | 'action' | 'callout' | 'link'

export type KGKind =
  | 'process'
  | 'step'
  | 'application'
  | 'role'
  | 'site'
  | 'valueStream'
  | 'opportunity'
  | 'initiative'
  | 'savingsRecord'
  | 'hoshinObjective'
  | 'document'
  | 'meeting'
  | 'decision'
  | 'action'

export type Predicate =
  | 'performedIn'
  | 'uses'
  | 'handsOffTo'
  | 'variantOf'
  | 'ownedBy'
  | 'measuredBy'
  | 'addressedBy'
  | 'realizesSavings'
  | 'alignedToObjective'
  | 'documentedIn'
  | 'hasOpportunity'
  | 'discussedIn'
  | 'assignedTo'

export interface Provenance {
  source: string
  sourceId: string
  capturedFrom: string
  capturedTo: string
  confidence: number
  syncedAt: string
}

export interface Step {
  id: string
  name: string
  role: string
  application: string
  minutes: number
  handoffs: number
  rework: number
  waste: WasteType
  evidence: number
  kgId: string
  standardAligned: boolean
}

export interface Variant {
  name: string
  share: number
  cycle: number
  rework: number
  path: string
}

export interface Process {
  id: string
  name: string
  site: string
  businessUnit: string
  valueStream: string
  owner: string
  summary: string
  applications: string[]
  people: number
  annualHours: number
  cycleMinutes: number
  reworkRate: number
  handoffs: number
  adherence: number
  confidence: number
  maturity: number
  classification: Classification
  status: 'discovered' | 'suppressed' | 'blocked'
  statusReason: string
  standard: string
  standardVersion: string
  staleDays: number
  kypId: string
  kgId: string
  steps: Step[]
  variants: Variant[]
}

export interface Opportunity {
  id: string
  title: string
  processId: string
  processName: string
  site: string
  waste: WasteType
  route: Route
  method: MethodKey
  hours: number
  errorReduction: number
  effortWeeks: number
  risk: number
  alignment: number
  automation: number
  confidence: number
  statutory: boolean
  status: 'new' | 'qualified' | 'promoted' | 'deferred'
  rationale: string
  owner: string
  kgId: string
}

export interface Initiative {
  id: string
  title: string
  opportunityId: string
  processId: string
  processName: string
  site: string
  method: MethodKey
  owner: string
  stage: 'plan' | 'do' | 'check' | 'act'
  due: string
  savingsHours: number
  savingsStage: SavingsStage
  validatedBy: string
  evidence: string
  waste: WasteType
  background: string
  target: string
  countermeasure: string
  result: string
}

export interface KGNode {
  id: string
  kind: KGKind
  name: string
  confidence: number
  review: 'confirmed' | 'suggested' | 'rejected'
  source: string
  sourceId: string
  validFrom: string
  processId?: string
  note?: string
}

export interface KGEdge {
  from: string
  predicate: Predicate
  to: string
  confidence: number
}

export interface MeetingBlock {
  id: string
  meetingId: string
  order: number
  kind: BlockKind
  text: string
  checked: boolean
  owner: string
  due?: string
  linkedKind?: string
  linkedId?: string
}

export interface Meeting {
  id: string
  title: string
  kind: MeetingKind
  date: string
  durationMinutes: number
  site: string
  owner: string
  attendees: string[]
  processId: string
  initiativeId: string
  status: 'planned' | 'notes' | 'done'
  summary: string
  recurring: boolean
  cadence: string
  kgId: string
}

export interface GovernanceItem {
  id: string
  title: string
  detail: string
  group: string
  status: 'done' | 'inProgress' | 'blocked' | 'notStarted'
  owner: string
}

export interface AuditEntry {
  id: string
  at: string
  actor: string
  action: string
  subject: string
  detail: string
}

export interface OpportunityScore {
  impact: number
  ease: number
  alignment: number
  automation: number
  riskPenalty: number
  total: number
  route: Route
  reasoning: string[]
}

export interface PrivacyPolicy {
  minimumGroupSize: number
  retentionDays: number
  provider: string
  region: string
  purpose: Purpose
  dataOwner: string
}

export interface PrivacyDecision {
  allowed: boolean
  action: 'allow' | 'mask' | 'suppress' | 'block'
  reason: string
  rule: string
}

export interface Citation {
  kind: 'kyp' | 'kg' | 'initiative' | 'policy' | 'computed' | 'meeting'
  ref: string
  label: string
}

export interface Answer {
  id: string
  question: string
  intent: string
  headline: string
  body: string
  citations: Citation[]
  toVerify: string[]
  confidence: number
}

export interface SavingsLine {
  initiativeId: string
  title: string
  processId: string
  waste: WasteType
  stage: SavingsStage
  hours: number
  validatedBy?: string
}
