export interface MiningEvent {
  caseId: string
  activity: string
  timestamp: number
  resource: string
  application: string
  attributes: Record<string, string>
  cost?: number
}

export interface MiningCase {
  id: string
  events: MiningEvent[]
  sequence: string[]
  start: number
  end: number
  cycle: number
  waiting: number
  rework: number
  handoffs: number
  resources: string[]
  attributes: Record<string, string>
  cost: number
  variant: string
}

export interface MinedActivity {
  name: string
  events: number
  cases: number
  wait: number
  rework: number
  handoffs: number
  resources: string[]
  automation: number
}

export interface MinedVariant { path: string; cases: number; share: number; cycle: number; rework: number }
export interface MinedEdge { from: string; to: string; count: number; wait: number }
export interface MiningPeriod { label: string; cases: number; cycle: number; rework: number }
export interface MiningAlert { id: string; severity: 'info' | 'warning' | 'critical'; title: string; detail: string }

export interface MinedProcess {
  cases: number
  events: number
  activities: MinedActivity[]
  variants: MinedVariant[]
  edges: MinedEdge[]
  caseRecords: MiningCase[]
  median: number
  p90: number
  mean: number
  reworkRate: number
  handoffRate: number
  cost: number
  periods: MiningPeriod[]
  alerts: MiningAlert[]
}

export interface MiningFilter {
  activity?: string
  resource?: string
  attributeKey?: string
  attributeValue?: string
  reworkOnly?: boolean
}

const hash = (value: string): string => {
  let h = 2166136261
  for (let i = 0; i < value.length; i++) { h ^= value.charCodeAt(i); h = Math.imul(h, 16777619) }
  return `case-${(h >>> 0).toString(16).padStart(8, '0')}`
}

const parseTimestamp = (value: string): number => {
  const iso = value.includes('T') ? value : value.replace(' ', 'T')
  const parsed = Date.parse(iso)
  return Number.isNaN(parsed) ? 0 : parsed
}

const csvEscape = (value: string) => `"${value.replaceAll('"', '""')}"`

const splitLine = (line: string): string[] => {
  const cells: string[] = []
  let current = ''
  let quoted = false
  for (let i = 0; i < line.length; i++) {
    const char = line[i]
    if (char === '"') {
      if (quoted && line[i + 1] === '"') { current += '"'; i++ } else quoted = !quoted
    } else if (char === ',' && !quoted) { cells.push(current); current = '' }
    else current += char
  }
  cells.push(current)
  return cells
}

export function parseEventCSV(text: string): MiningEvent[] {
  const lines = text.split(/\r?\n/).filter(Boolean)
  if (lines.length < 2) return []
  const header = splitLine(lines[0] ?? '').map(h => h.trim().toLowerCase())
  const index = (name: string) => header.indexOf(name)
  const caseAt = index('case_id')
  const activityAt = index('activity')
  const timeAt = index('timestamp')
  const resourceAt = index('resource')
  const appAt = index('application')
  const costAt = index('cost')
  if (caseAt < 0 || activityAt < 0 || timeAt < 0) return []
  const core = new Set([caseAt, activityAt, timeAt, resourceAt, appAt, costAt])
  const extras = header.map((name, i) => ({ name, i })).filter(x => !core.has(x.i) && x.name)
  const events: MiningEvent[] = []
  for (const line of lines.slice(1)) {
    const cells = splitLine(line)
    const caseId = cells[caseAt]?.trim()
    const activity = cells[activityAt]?.trim()
    const time = parseTimestamp(cells[timeAt]?.trim() ?? '')
    if (!caseId || !activity || !time) continue
    const attributes: Record<string, string> = {}
    for (const extra of extras) {
      const value = cells[extra.i]?.trim()
      if (value) attributes[extra.name] = value
    }
    events.push({
      caseId: hash(caseId), activity, timestamp: time,
      resource: cells[resourceAt]?.trim() || 'Unassigned',
      application: cells[appAt]?.trim() || '',
      attributes,
      cost: Number(cells[costAt]) || undefined,
    })
  }
  return events.sort((a, b) => a.timestamp - b.timestamp)
}

export function sampleCSV(): string {
  const lines = ['case_id,activity,timestamp,resource,application,case_type,region,cost']
  const base = Date.UTC(2026, 0, 1, 8, 0, 0)
  const fmt = (ms: number) => new Date(ms).toISOString().slice(0, 19).replace('T', ' ')
  for (let i = 0; i < 24; i++) {
    const caseId = `ORD-2026-${String(i + 1).padStart(4, '0')}`
    let time = base + (i % 12) * 86_400_000 + i * 1_800_000
    const variant = i % 3
    const type = variant === 2 ? 'Expedite' : 'Standard'
    const region = i % 2 === 0 ? 'DE' : 'PL'
    const cost = variant === 2 ? 36 : 24
    const add = (activity: string, minutes: number, role: string, app: string) => {
      lines.push([caseId, activity, fmt(time), role, app, type, region, String(cost)].map(csvEscape).join(','))
      time += minutes * 60_000
    }
    add('Receive order', 6, 'Order Desk', 'Outlook')
    add('Check customer master', 9, 'Order Desk', 'SAP S/4HANA')
    if (variant === 2) add('Clear exception queue', 11 + (i % 4), 'Order Desk', 'Salesforce')
    add('Validate pricing', 12, i % 2 === 0 ? 'Pricing Analyst' : 'Order Desk', 'Salesforce')
    if (variant === 1) add('Release credit hold', 4 + (i % 3), 'Credit Manager', 'SAP S/4HANA')
    add('Create sales order', 14, 'Order Desk', 'SAP S/4HANA')
    if (variant === 2) add('Clear exception queue', 8, 'Order Desk', 'Salesforce')
    add('Send confirmation', 3, 'Order Desk', 'Outlook')
  }
  return lines.join('\n')
}

export const buildCases = (events: MiningEvent[]): MiningCase[] => {
  const grouped = new Map<string, MiningEvent[]>()
  for (const event of events) {
    const list = grouped.get(event.caseId) ?? []
    list.push(event)
    grouped.set(event.caseId, list)
  }
  return [...grouped.entries()].map(([id, list]) => {
    const ordered = [...list].sort((a, b) => a.timestamp - b.timestamp)
    const sequence = ordered.map(e => e.activity)
    const attributes: Record<string, string> = {}
    for (const event of ordered) for (const [key, value] of Object.entries(event.attributes)) if (!attributes[key]) attributes[key] = value
    let waiting = 0
    let handoffs = 0
    for (let i = 1; i < ordered.length; i++) {
      waiting += Math.max(0, (ordered[i]!.timestamp - ordered[i - 1]!.timestamp) / 60_000)
      if (ordered[i]!.resource !== ordered[i - 1]!.resource) handoffs++
    }
    const first = ordered[0]!
    const last = ordered[ordered.length - 1]!
    return {
      id, events: ordered, sequence,
      start: first.timestamp, end: last.timestamp,
      cycle: Math.max(0, (last.timestamp - first.timestamp) / 60_000),
      waiting, rework: sequence.length - new Set(sequence).size, handoffs,
      resources: [...new Set(ordered.map(e => e.resource))].sort(),
      attributes, cost: ordered.reduce((sum, e) => sum + (e.cost ?? 0), 0),
      variant: sequence.join(' → '),
    }
  }).sort((a, b) => a.start - b.start)
}

const percentile = (values: number[], p: number) => {
  if (!values.length) return 0
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.min(sorted.length - 1, Math.max(0, Math.round((sorted.length - 1) * p)))] ?? 0
}

export function mine(events: MiningEvent[]): MinedProcess {
  const caseRecords = buildCases(events)
  const activityMap = new Map<string, MiningActivityAccumulator>()
  const edgeMap = new Map<string, { count: number; waits: number[] }>()
  const variants = new Map<string, { cases: number; cycles: number[]; rework: number; events: number }>()
  let totalEvents = 0
  let repeated = 0
  let handoffs = 0
  for (const record of caseRecords) {
    const key = record.variant
    const entry = variants.get(key) ?? { cases: 0, cycles: [], rework: 0, events: 0 }
    entry.cases++
    entry.cycles.push(record.cycle)
    entry.rework += record.rework
    entry.events += record.events.length
    variants.set(key, entry)
    const seen = new Set<string>()
    let previous: MiningEvent | undefined
    for (const event of record.events) {
      totalEvents++
      const activity = activityMap.get(event.activity) ?? { events: 0, cases: new Set(), waits: [], rework: 0, handoffs: 0, resources: new Set() }
      activity.events++
      activity.cases.add(record.id)
      activity.resources.add(event.resource)
      if (seen.has(event.activity)) { activity.rework++; repeated++ }
      seen.add(event.activity)
      if (previous) {
        const wait = Math.max(0, (event.timestamp - previous.timestamp) / 60_000)
        activity.waits.push(wait)
        if (previous.resource !== event.resource) { activity.handoffs++; handoffs++ }
        const edgeKey = `${previous.activity}→${event.activity}`
        const edge = edgeMap.get(edgeKey) ?? { count: 0, waits: [] }
        edge.count++
        edge.waits.push(wait)
        edgeMap.set(edgeKey, edge)
      }
      activityMap.set(event.activity, activity)
      previous = event
    }
  }
  const activities: MinedActivity[] = [...activityMap.entries()].map(([name, value]) => ({
    name, events: value.events, cases: value.cases.size,
    wait: value.waits.length ? value.waits.reduce((a, b) => a + b, 0) / value.waits.length : 0,
    rework: value.rework, handoffs: value.handoffs,
    resources: [...value.resources].sort(),
    automation: Math.min(1, 0.45 * Math.min(1, value.events / 100) + 0.3 * Math.min(1, value.rework / Math.max(1, value.events)) + 0.25 * (value.resources.size <= 1 ? 1 : 0.5)),
  })).sort((a, b) => b.events - a.events)
  const edges: MinedEdge[] = [...edgeMap.entries()].map(([key, value]) => {
    const [from, to] = key.split('→')
    return { from: from ?? '', to: to ?? '', count: value.count, wait: value.waits.reduce((a, b) => a + b, 0) / value.waits.length }
  }).sort((a, b) => b.count - a.count)
  const minedVariants: MinedVariant[] = [...variants.entries()].map(([path, value]) => ({
    path, cases: value.cases, share: caseRecords.length ? value.cases / caseRecords.length : 0,
    cycle: value.cycles.reduce((a, b) => a + b, 0) / value.cycles.length,
    rework: value.events ? value.rework / value.events : 0,
  })).sort((a, b) => b.cases - a.cases)
  const cycles = caseRecords.map(r => r.cycle)
  const periodMap = new Map<string, MiningCase[]>()
  for (const record of caseRecords) {
    const date = new Date(record.start)
    const onejan = new Date(date.getFullYear(), 0, 1)
    const week = Math.ceil((((date.getTime() - onejan.getTime()) / 86_400_000) + onejan.getDay() + 1) / 7)
    const key = `${date.getFullYear()}-W${String(week).padStart(2, '0')}`
    periodMap.set(key, [...(periodMap.get(key) ?? []), record])
  }
  const periods: MiningPeriod[] = [...periodMap.entries()].slice(-12).map(([label, records]) => ({
    label, cases: records.length, cycle: percentile(records.map(r => r.cycle), 0.5),
    rework: records.reduce((sum, r) => sum + r.rework, 0) / Math.max(1, records.reduce((sum, r) => sum + r.events.length, 0)),
  }))
  const reworkRate = totalEvents ? repeated / totalEvents : 0
  const result: MinedProcess = {
    cases: caseRecords.length, events: totalEvents, activities, variants: minedVariants, edges,
    caseRecords, median: percentile(cycles, 0.5), p90: percentile(cycles, 0.9),
    mean: cycles.length ? cycles.reduce((a, b) => a + b, 0) / cycles.length : 0,
    reworkRate, handoffRate: totalEvents ? handoffs / Math.max(1, totalEvents - caseRecords.length) : 0,
    cost: caseRecords.reduce((sum, r) => sum + r.cost, 0), periods, alerts: [],
  }
  result.alerts = alerts(result)
  return result
}

interface MiningActivityAccumulator {
  events: number
  cases: Set<string>
  waits: number[]
  rework: number
  handoffs: number
  resources: Set<string>
}

export function filterEvents(events: MiningEvent[], filter: MiningFilter): MiningEvent[] {
  if (!filter.activity && !filter.resource && !filter.attributeKey && !filter.attributeValue && !filter.reworkOnly) return events
  let scoped = events.filter(event => {
    if (filter.activity && event.activity !== filter.activity) return false
    if (filter.resource && event.resource !== filter.resource) return false
    if (filter.attributeKey && filter.attributeValue && event.attributes[filter.attributeKey] !== filter.attributeValue) return false
    return true
  })
  if (filter.reworkOnly) {
    const kept = buildCases(scoped).filter(c => c.rework > 0).map(c => c.id)
    scoped = scoped.filter(e => kept.includes(e.caseId))
  }
  return scoped
}

export function conformance(events: MiningEvent[], reference: string[]) {
  const cases = buildCases(events)
  if (!reference.length || !cases.length) return { fitness: 0, exact: 0, total: cases.length, token: 0, missing: 0, remaining: 0, missingActivities: [], extraActivities: [] }
  let exact = 0
  let fitness = 0
  let missingTokens = 0
  let remainingTokens = 0
  const missing = new Set<string>()
  const extra = new Set<string>()
  for (const record of cases) {
    if (record.sequence.join('|') === reference.join('|')) exact++
    fitness += lcs(record.sequence, reference).length / reference.length
    record.sequence.forEach(a => { if (!reference.includes(a)) extra.add(a) })
    reference.forEach(a => { if (!record.sequence.includes(a)) missing.add(a) })
    let next = 0
    for (const activity of record.sequence) {
      if (next < reference.length && activity === reference[next]) next++
      else if (next < reference.length && reference.slice(next).includes(activity)) {
        missingTokens++
        while (next < reference.length && reference[next] !== activity) next++
        next++
      }
    }
    remainingTokens += Math.max(0, reference.length - next)
  }
  const token = Math.max(0, 1 - (missingTokens + remainingTokens) / Math.max(1, cases.reduce((sum, c) => sum + c.sequence.length, 0) + reference.length * cases.length))
  return { fitness: fitness / cases.length, exact, total: cases.length, token, missing: missingTokens, remaining: remainingTokens, missingActivities: [...missing], extraActivities: [...extra] }
}

const lcs = (a: string[], b: string[]): string[] => {
  const table = Array.from({ length: a.length + 1 }, () => Array<number>(b.length + 1).fill(0))
  for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++) {
    table[i]![j] = a[i - 1] === b[j - 1] ? table[i - 1]![j - 1]! + 1 : Math.max(table[i - 1]![j]!, table[i]![j - 1]!)
  }
  const result: string[] = []
  let i = a.length, j = b.length
  while (i && j) {
    if (a[i - 1] === b[j - 1]) { result.push(a[i - 1]!); i--; j-- }
    else if (table[i - 1]![j]! >= table[i]![j - 1]!) i--
    else j--
  }
  return result.reverse()
}

export function simulate(cases: MiningCase[], automate: Set<string>, remove: Set<string>, reworkReduction: number, waitReduction: number) {
  if (!cases.length) return { baseline: 0, projected: 0, saved: 0, affected: 0 }
  const baseline: number[] = []
  const projected: number[] = []
  let affected = 0
  for (const record of cases) {
    let saved = 0
    let touched = false
    const seen = new Set<string>()
    for (let i = 1; i < record.events.length; i++) {
      const current = record.events[i]!
      const previous = record.events[i - 1]!
      const wait = Math.max(0, (current.timestamp - previous.timestamp) / 60_000)
      if (remove.has(current.activity)) { saved += wait; touched = true }
      else if (automate.has(current.activity)) { saved += wait * 0.8; touched = true }
      if (seen.has(current.activity)) { saved += wait * reworkReduction; touched = true }
      seen.add(current.activity)
    }
    const remaining = Math.max(0, record.waiting - saved)
    baseline.push(record.cycle)
    projected.push(Math.max(0, record.cycle - saved - remaining * waitReduction))
    if (touched || waitReduction > 0) affected++
  }
  const base = percentile(baseline, 0.5)
  const proj = percentile(projected, 0.5)
  return { baseline: base, projected: proj, saved: Math.max(0, base - proj), affected }
}

export function alerts(mined: MinedProcess): MiningAlert[] {
  const result: MiningAlert[] = []
  if (mined.reworkRate > 0.05) result.push({ id: 'rework', severity: mined.reworkRate > 0.2 ? 'critical' : 'warning', title: `Rework is ${Math.round(mined.reworkRate * 100)}%`, detail: `${mined.caseRecords.filter(c => c.rework > 0).length} of ${mined.cases} cases repeat a step.` })
  const bottleneck = [...mined.activities].sort((a, b) => b.wait - a.wait)[0]
  if (bottleneck && bottleneck.wait > 8) result.push({ id: 'wait', severity: bottleneck.wait > 20 ? 'critical' : 'warning', title: `${bottleneck.name} waits ${Math.round(bottleneck.wait)} min`, detail: 'The largest average wait in the current view.' })
  if (mined.variants[0] && mined.variants[0].share < 0.5 && mined.cases >= 5) result.push({ id: 'variants', severity: 'warning', title: `Long tail: ${mined.variants.length} variants`, detail: `The top path is only ${Math.round(mined.variants[0].share * 100)}% of cases.` })
  if (mined.handoffRate > 0.3) result.push({ id: 'handoffs', severity: 'info', title: `High handoff rate: ${Math.round(mined.handoffRate * 100)}%`, detail: 'Work changes role frequently.' })
  return result
}

export function rootCauses(cases: MiningCase[], outcome: 'slow' | 'rework') {
  if (!cases.length) return []
  const overallCycle = cases.reduce((sum, c) => sum + c.cycle, 0) / cases.length
  const overallRework = cases.filter(c => c.rework > 0).length / cases.length
  const dimensions = new Map<string, Map<string, MiningCase[]>>()
  for (const record of cases) for (const [key, value] of Object.entries(record.attributes)) {
    if (!dimensions.has(key)) dimensions.set(key, new Map())
    const map = dimensions.get(key)!
    map.set(value, [...(map.get(value) ?? []), record])
  }
  const result: Array<{ id: string; dimension: string; value: string; cases: number; cycle: number; rework: number; impact: number }> = []
  for (const [dimension, values] of dimensions) for (const [value, group] of values) {
    if (group.length < Math.max(2, Math.floor(cases.length / 12))) continue
    const cycle = group.reduce((sum, c) => sum + c.cycle, 0) / group.length
    const rework = group.filter(c => c.rework > 0).length / group.length
    result.push({ id: `${dimension}=${value}`, dimension, value, cases: group.length, cycle, rework, impact: outcome === 'slow' ? ((cycle - overallCycle) * group.length) / 60 : (rework - overallRework) * group.length })
  }
  return result.sort((a, b) => Math.abs(b.impact) - Math.abs(a.impact)).slice(0, 8)
}
