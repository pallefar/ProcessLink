import type { MiningEvent } from './mining'

export interface OcelObject { id: string; type: string; label: string }
export interface OcelInteraction { from: string; to: string; events: number }
export interface OcelModel {
  objects: OcelObject[]
  objectTypes: Array<{ type: string; count: number }>
  interactions: OcelInteraction[]
  multiObjectEvents: number
}

export function buildOcel(events: MiningEvent[], keys: string[]): OcelModel {
  const objects = new Map<string, OcelObject>()
  const interactions = new Map<string, OcelInteraction>()
  let multiObjectEvents = 0
  for (const event of events) {
    const ids = [`case:${event.caseId}`]
    objects.set(ids[0]!, { id: ids[0]!, type: 'case', label: event.caseId })
    for (const key of keys) {
      const value = event.attributes[key]
      if (!value) continue
      const type = key.toLowerCase().replaceAll(' ', '_')
      const id = `${type}:${value}`
      objects.set(id, { id, type, label: value })
      ids.push(id)
    }
    if (ids.length > 2) multiObjectEvents++
    for (let i = 0; i < ids.length; i++) {
      for (let j = i + 1; j < ids.length; j++) {
        const a = ids[i]!
        const b = ids[j]!
        const from = a < b ? a : b
        const to = a < b ? b : a
        const key = `${from}|${to}`
        const entry = interactions.get(key) ?? { from, to, events: 0 }
        entry.events++
        interactions.set(key, entry)
      }
    }
  }
  const counts = new Map<string, number>()
  for (const object of objects.values()) counts.set(object.type, (counts.get(object.type) ?? 0) + 1)
  return {
    objects: [...objects.values()],
    objectTypes: [...counts.entries()].map(([type, count]) => ({ type, count })).sort((a, b) => a.type.localeCompare(b.type)),
    interactions: [...interactions.values()].sort((a, b) => b.events - a.events),
    multiObjectEvents,
  }
}

export interface PeerBenchmark {
  id: string
  label: string
  cohort: string
  medianCycleMinutes: number
  p90CycleMinutes: number
  reworkRate: number
  automationRatio: number
  sampleCases: number
  note: string
}

export const PEER_BENCHMARKS: PeerBenchmark[] = [
  { id: 'finance-eu-mid', label: 'Finance · EU mid-size', cohort: 'AP / invoice', medianCycleMinutes: 1080, p90CycleMinutes: 3600, reworkRate: 0.22, automationRatio: 0.35, sampleCases: 420, note: 'Illustrative cohort; replace with a governed feed.' },
  { id: 'order-de-mid', label: 'Order desk · DE mid-size', cohort: 'Order-to-cash', medianCycleMinutes: 2520, p90CycleMinutes: 7200, reworkRate: 0.18, automationRatio: 0.42, sampleCases: 610, note: 'Illustrative cohort; replace with a governed feed.' },
  { id: 'service-eu-mid', label: 'Customer service · EU mid-size', cohort: 'Case triage', medianCycleMinutes: 1920, p90CycleMinutes: 5400, reworkRate: 0.14, automationRatio: 0.38, sampleCases: 880, note: 'Illustrative cohort; replace with a governed feed.' },
]

export const closestPeer = (medianCycleMinutes: number): PeerBenchmark =>
  [...PEER_BENCHMARKS].sort((a, b) => Math.abs(a.medianCycleMinutes - medianCycleMinutes) - Math.abs(b.medianCycleMinutes - medianCycleMinutes))[0]!
