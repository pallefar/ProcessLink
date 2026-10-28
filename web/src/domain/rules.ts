import type {
  Answer, Citation, Classification, Destination, Initiative, MethodKey, Opportunity,
  OpportunityScore, PrivacyDecision, PrivacyPolicy, Purpose, Route, SavingsLine,
  SavingsStage, WasteType,
} from './types'

export const RATE_PER_HOUR = 52
export const STALE_AFTER_DAYS = 14

// MARK: Formatting

export const fmt = {
  hours(value: number): string {
    return `${Math.round(value).toLocaleString('en-GB')} h`
  },
  hoursPerYear(value: number): string {
    return `${fmt.hours(value)}/yr`
  },
  euro(value: number): string {
    return `€${Math.round(value).toLocaleString('en-GB')}`
  },
  money(hours: number): string {
    return fmt.euro(hours * RATE_PER_HOUR)
  },
  percent(rate: number): string {
    return `${Math.round(rate * 100)}%`
  },
  minutes(value: number): string {
    return value < 60 ? `${Math.round(value)} min` : `${(value / 60).toFixed(1)} h`
  },
  day(iso: string): string {
    return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
  },
  ago(iso: string): string {
    const days = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 86_400_000))
    return days < 1 ? 'today' : days === 1 ? 'yesterday' : `${days} days ago`
  },
}

// MARK: Scoring

export function routeFor(o: { statutory: boolean; waste: WasteType; automation: number; effortWeeks: number }): Route {
  if (o.statutory) return 'standardize'
  switch (o.waste) {
    case 'handoffs':
    case 'waiting':
      return o.automation >= 0.55 && o.effortWeeks <= 10 ? 'automate' : 'simplify'
    case 'overProcessing':
    case 'defects':
      return 'simplify'
    case 'contextSwitching':
    case 'rework':
      return 'standardize'
    case 'backlog':
      return 'eliminate'
    case 'unusedTalent':
      return o.automation >= 0.5 ? 'automate' : 'standardize'
  }
}

/** Same arithmetic as `OpportunityScoring` in ProcessLinkKit. */
export function scoreOpportunity(o: Opportunity): OpportunityScore {
  const hourComponent = Math.min(1, Math.max(0, o.hours) / 1200) * 70
  const errorComponent = Math.min(1, Math.max(0, o.errorReduction) / 100) * 30
  const impact = Math.min(100, hourComponent + errorComponent)
  const ease = Math.min(100, Math.max(10, 100 - Math.max(0, o.effortWeeks - 1) * 6))
  const alignment = Math.min(100, Math.max(0, Math.min(5, Math.max(1, o.alignment)) / 5 * 100))
  const automation = Math.min(100, Math.max(0, o.automation * 100))
  const riskPenalty = (Math.min(5, Math.max(1, o.risk)) - 1) * 5
  const confidence = Math.min(100, Math.max(0, o.confidence * 100))

  const raw = 0.42 * impact + 0.22 * ease + 0.18 * alignment + 0.10 * automation + 0.08 * confidence
  const total = Math.min(100, Math.max(0, raw - riskPenalty))

  const reasoning = [
    `${fmt.hoursPerYear(o.hours)} of mined effort drives ${Math.round(hourComponent)} of the 100 impact points.`,
    `A ${Math.round(o.errorReduction)} percent error reduction adds ${Math.round(errorComponent)} points.`,
    `An estimated ${Math.round(o.effortWeeks)} weeks of effort gives an ease score of ${Math.round(ease)}.`,
    `Alignment ${o.alignment}/5 contributes ${Math.round(0.18 * alignment)} weighted points.`,
    ...(riskPenalty > 0 ? [`Risk ${o.risk}/5 subtracts ${Math.round(riskPenalty)} points.`] : []),
    ...(o.confidence < 0.75
      ? [`Confidence is ${fmt.percent(o.confidence)}; this needs a human check before it is committed.`]
      : []),
  ]

  return { impact, ease, alignment, automation, riskPenalty, total, route: routeFor(o), reasoning }
}

export function recommendMethod(waste: WasteType, route: Route, statutory: boolean): { method: MethodKey; reason: string } {
  if (statutory) {
    return {
      method: 'a3',
      reason: 'A statutory or human-only step keeps its human control. Use A3 to make the control explicit and measurable; automation is excluded by policy.',
    }
  }
  if (route === 'automate') {
    return {
      method: 'kaizen',
      reason: 'Automation follows a kaizen that proves the simplified path. Run the event first, then hand the stable path to automation.',
    }
  }
  if (route === 'eliminate') {
    return { method: 'vsm', reason: 'Removing work starts with seeing the flow. Map the stream before deleting a step.' }
  }
  switch (waste) {
    case 'handoffs':
    case 'waiting':
      return { method: 'vsm', reason: 'Handoffs and waiting are visible only end to end. The value stream map shows the queue between roles.' }
    case 'overProcessing':
      return { method: 'standardWork', reason: 'Duplicate checks disappear when the standard path is written once and followed.' }
    case 'rework':
    case 'defects':
      return { method: 'a3', reason: 'Rework needs a cause before a countermeasure. A3 keeps the analysis honest.' }
    case 'contextSwitching':
      return { method: '5s', reason: 'Switching applications is a workplace-organisation problem: put the information where the work happens.' }
    case 'unusedTalent':
      return { method: 'standardWork', reason: 'Copy-paste is not the job. Write the standard so the skilled part stays with the person.' }
    case 'backlog':
      return { method: 'dailyManagement', reason: 'A backlog needs a daily read against target, not a one-off project.' }
  }
}

// MARK: Privacy

export const CLASSIFICATION_DETAIL: Record<Classification, string> = {
  public: 'Safe for any approved destination.',
  internal: 'Stays in the tenant or an approved AI gateway.',
  confidential: 'Needs named approval before it moves.',
  restricted: 'Never leaves discovery. Blocked by policy.',
}

export function evaluate(input: {
  groupSize: number
  classification: Classification
  destination: Destination
  purpose: Purpose
  piiFindings?: number
  policy: PrivacyPolicy
}): PrivacyDecision {
  const { groupSize, classification, destination, purpose, policy } = input
  const pii = input.piiFindings ?? 0

  if (purpose === 'individualPerformance') {
    return {
      allowed: false, action: 'block',
      reason: 'ProcessLink is for process and system improvement only. Individual performance, monitoring or HR use is out of purpose.',
      rule: 'privacy-guard/1 · purpose limitation',
    }
  }
  if (classification === 'restricted') {
    return {
      allowed: false, action: 'block',
      reason: 'This record is classified Restricted. Restricted content never enters ProcessLink, not even for a local report.',
      rule: 'privacy-guard/1 · classification gate',
    }
  }
  if (groupSize < policy.minimumGroupSize) {
    const allowed = destination === 'localView' && groupSize > 0
    return {
      allowed, action: allowed ? 'suppress' : 'block',
      reason: allowed
        ? `A group of ${groupSize} is below the ${policy.minimumGroupSize}-person threshold. The aggregate is hidden; only the fact that it exists is shown.`
        : `A group of ${groupSize} cannot be sent to ${destination}. The minimum group size is ${policy.minimumGroupSize}.`,
      rule: 'privacy-guard/1 · minimum group size',
    }
  }
  if (classification === 'confidential' && destination !== 'localView') {
    return {
      allowed: false, action: 'block',
      reason: 'Confidential data needs a named approval before it leaves this Mac.',
      rule: 'privacy-guard/1 · confidential transfer',
    }
  }
  if (destination === 'aiGateway' && pii > 0) {
    return {
      allowed: false, action: 'mask',
      reason: `${pii} possible personal-data item${pii === 1 ? '' : 's'} found. Mask them before any AI call.`,
      rule: 'privacy-guard/1 · PII before API',
    }
  }
  return {
    allowed: true, action: 'allow',
    reason: `${classification} data may go to ${destination} for process improvement under the current policy.`,
    rule: 'privacy-guard/1 · default allow',
  }
}

export function canDisplay(process: { people: number; classification: Classification }, policy: PrivacyPolicy): boolean {
  const decision = evaluate({
    groupSize: process.people, classification: process.classification,
    destination: 'localView', purpose: 'processImprovement', policy,
  })
  return decision.allowed && decision.action === 'allow'
}

const PII_PATTERNS: Array<{ name: string; token: string; regex: RegExp }> = [
  { name: 'email addresses', token: 'email', regex: /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi },
  { name: 'IBANs', token: 'iban', regex: /\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{2,4}){4,8}\b/gi },
  { name: 'employee ids', token: 'employee-id', regex: /\bEMP[- ]?\d{4,}\b/gi },
  { name: 'phone numbers', token: 'phone', regex: /(?<!\d)\+?\d[\d\s().-]{8,}\d(?!\d)/g },
  { name: 'long identifier numbers', token: 'identifier', regex: /(?<!\d)\d{9,}(?!\d)/g },
]

export interface PIIScan {
  counts: Record<string, number>
  masked: string
  total: number
}

export function scanPII(text: string): PIIScan {
  let masked = text
  const counts: Record<string, number> = {}
  for (const pattern of PII_PATTERNS) {
    const matches = masked.match(pattern.regex)
    if (!matches?.length) continue
    counts[pattern.name] = (counts[pattern.name] ?? 0) + matches.length
    masked = masked.replace(pattern.regex, `[redacted:${pattern.token}]`)
  }
  return { counts, masked, total: Object.values(counts).reduce((sum, n) => sum + n, 0) }
}

// MARK: Savings

export function savingsTotal(lines: SavingsLine[], stage: SavingsStage): number {
  const best = new Map<string, SavingsLine>()
  for (const line of lines) {
    const key = `${line.processId}:${line.waste}`
    const current = best.get(key)
    const rank = (s: SavingsStage) => (s === 'validated' ? 2 : s === 'committed' ? 1 : 0)
    if (!current || rank(line.stage) > rank(current.stage)
      || (rank(line.stage) === rank(current.stage) && line.hours > current.hours)) {
      best.set(key, line)
    }
  }
  return [...best.values()].filter(line => line.stage === stage).reduce((sum, line) => sum + line.hours, 0)
}

export interface SavingsConflict {
  key: string
  processId: string
  waste: WasteType
  initiativeIds: string[]
  hours: number[]
}

export function savingsConflicts(lines: SavingsLine[]): SavingsConflict[] {
  const grouped = new Map<string, SavingsLine[]>()
  for (const line of lines) {
    if (line.stage === 'estimated') continue
    const key = `${line.processId}:${line.waste}`
    grouped.set(key, [...(grouped.get(key) ?? []), line])
  }
  const conflicts: SavingsConflict[] = []
  for (const [key, group] of grouped) {
    const ids = [...new Set(group.map(line => line.initiativeId))]
    const first = group[0]
    if (!first || ids.length < 2) continue
    conflicts.push({ key, processId: first.processId, waste: first.waste, initiativeIds: ids, hours: group.map(line => line.hours) })
  }
  return conflicts
}

export function initiativeLine(initiative: Initiative): SavingsLine {
  return {
    initiativeId: initiative.id, title: initiative.title, processId: initiative.processId,
    waste: initiative.waste, stage: initiative.savingsStage, hours: initiative.savingsHours,
    validatedBy: initiative.validatedBy || undefined,
  }
}

// MARK: Ask

export function buildCitation(citation: Citation): Citation {
  return citation
}

export type { Answer }
