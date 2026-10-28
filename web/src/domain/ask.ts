import type { Answer, Citation, Meeting, MeetingBlock, Opportunity, Process } from './types'
import { fmt } from './rules'

const stepList = (processes: Process[]) => processes.flatMap(process => process.steps.map(step => ({ process, step })))

function cite(process: Process, stepName?: string): Citation[] {
  const citations: Citation[] = [{ kind: 'kg', ref: process.kgId, label: process.name }]
  if (stepName) {
    const step = process.steps.find(s => s.name === stepName)
    if (step) citations.push({ kind: 'kg', ref: step.kgId, label: step.name })
  }
  citations.push({ kind: 'kyp', ref: process.kypId, label: process.name })
  return citations
}

export const SUGGESTIONS = [
  'Where do handoffs create the most rework?',
  'Which standard work is least followed?',
  'What would automating order intake save?',
  'Which processes have the most variants?',
  'What did we decide about pricing?',
  'What actions are still open?',
]

/** Deterministic, citation-first answer engine — the local provider. */
export function answer(question: string, processes: Process[], opportunities: Opportunity[], meetings: Meeting[] = [], blocks: MeetingBlock[] = []): Answer {
  const q = question.trim()
  const lower = q.toLowerCase()
  const id = crypto.randomUUID()
  const visible = processes.filter(p => p.status === 'discovered' && p.people >= 10)

  if (lower.includes('privacy') || lower.includes('gdpr') || lower.includes('works council') || lower.includes('legal')) {
    return {
      id, question: q, intent: 'governance',
      headline: 'No production use until the launch checklist is signed',
      body: 'ProcessLink is for process and system improvement only. Before production: a DPIA, legal review per country, works-council consultation where required, a transparency notice, a retention schedule and a named data owner. In the product, groups below the threshold are suppressed, Restricted content is refused, and personal-data patterns are masked before any AI call.',
      citations: [
        { kind: 'policy', ref: 'privacy-guard/1', label: 'ProcessLink privacy policy' },
        { kind: 'policy', ref: 'governance/launch-checklist', label: 'Launch checklist' },
      ],
      toVerify: ['DPIA status by country', 'Works-council agreement scope'],
      confidence: 0.95,
    }
  }

  if (lower.includes('decid') || lower.includes('meeting') || lower.includes('minutes')) {
    const decisions = blocks.filter(b => b.kind === 'decision' && b.text.trim())
    const named = meetings.find(m => lower.includes(m.title.toLowerCase()))
    const scoped = named ? decisions.filter(b => b.meetingId === named.id) : decisions
    if (scoped.length === 0) {
      return {
        id, question: q, intent: 'decisions',
        headline: 'No decision is recorded for that scope',
        body: `ProcessLink holds ${meetings.length} meeting page${meetings.length === 1 ? '' : 's'}, but none records a decision for this scope. That is an absence of evidence, not evidence of no decision.`,
        citations: meetings.slice(0, 3).map(m => ({ kind: 'meeting', ref: m.kgId, label: m.title })),
        toVerify: ['Check the minutes or ask the meeting owner'], confidence: 0.6,
      }
    }
    return {
      id, question: q, intent: 'decisions',
      headline: 'Recorded decisions',
      body: scoped.slice(0, 4).map(item => {
        const meeting = meetings.find(m => m.id === item.meetingId)
        return `${meeting?.title ?? 'Meeting'} (${new Date(meeting?.date ?? Date.now()).toLocaleDateString('en-GB')}): ${item.text}`
      }).join('\n') + '\n\nA decision note records what the room agreed. It is not a validated outcome.',
      citations: [...new Set(scoped.map(b => b.meetingId))].map(id => {
        const meeting = meetings.find(m => m.id === id)
        return { kind: 'meeting' as const, ref: meeting?.kgId ?? id, label: meeting?.title ?? 'Meeting' }
      }),
      toVerify: ['Confirm the minutes were approved'], confidence: 0.84,
    }
  }

  if (lower.includes('action') || lower.includes('follow-up') || lower.includes('follow up')) {
    const open = blocks.filter(b => b.kind === 'action' && !b.checked)
    const scoped = open.slice(0, 5)
    return {
      id, question: q, intent: 'actions',
      headline: `${open.length} open action${open.length === 1 ? '' : 's'}`,
      body: scoped.map(item => {
        const meeting = meetings.find(m => m.id === item.meetingId)
        return `• ${item.text || 'Untitled action'} — ${item.owner || 'unassigned'}${item.due ? `, due ${new Date(item.due).toLocaleDateString('en-GB')}` : ''}${meeting ? ` · ${meeting.title}` : ''}`
      }).join('\n') + '\n\nAn action is a commitment, not a result. Promote it to an initiative when it is real improvement work.',
      citations: [...new Set(scoped.map(b => b.meetingId))].map(id => {
        const meeting = meetings.find(m => m.id === id)
        return { kind: 'meeting' as const, ref: meeting?.kgId ?? id, label: meeting?.title ?? 'Meeting' }
      }),
      toVerify: ['Promote any action that is really improvement work'], confidence: 0.86,
    }
  }

  if (lower.includes('handoff') || lower.includes('rework')) {
    const ranked = stepList(visible)
      .filter(({ step }) => step.handoffs > 0 && step.rework > 0.05)
      .sort((a, b) => b.step.handoffs * b.step.rework * b.step.evidence - a.step.handoffs * a.step.rework * a.step.evidence)
      .slice(0, 3)
    const first = ranked[0]
    if (!first) {
      return {
        id, question: q, intent: 'handoffs',
        headline: 'No handoff-driven rework found',
        body: 'No step both hands work off and carries rework in the current window. Confirm the capture window before reading it as good news.',
        citations: [], toVerify: ['Confirm the KYP.ai capture window'], confidence: 0.6,
      }
    }
    return {
      id, question: q, intent: 'handoffs',
      headline: `Handoffs concentrate rework at ${first.step.name}`,
      body: ranked.map(({ process, step }, index) =>
        `${index + 1}. ${step.name} — ${process.name}, ${process.site}. ${step.handoffs} handoff${step.handoffs === 1 ? '' : 's'}, ${fmt.percent(step.rework)} of its touches rework, on ${step.application}.`
      ).join('\n') + `\n\nEach handoff adds a queue and a re-key. The value stream map for ${first.process.name} is generated from these steps, with the loop drawn where the rework returns.`,
      citations: ranked.flatMap(({ process, step }) => cite(process, step.name)),
      toVerify: ['Handoff counts are mined events, not a judgement about the people who do them.'],
      confidence: 0.9,
    }
  }

  if (lower.includes('standard') || lower.includes('adherence') || lower.includes('follow')) {
    const ranked = [...visible].sort((a, b) => a.adherence - b.adherence).slice(0, 3)
    const lowest = ranked[0]
    if (!lowest) return fallback(id, q, processes, opportunities)
    return {
      id, question: q, intent: 'adherence',
      headline: `${lowest.name} deviates most from its documented standard`,
      body: ranked.map(p => `${p.name} (${p.site}): ${fmt.percent(p.adherence)} adherence across ${p.variants.length} variants.`).join('\n')
        + '\n\nA low adherence number has two readings: the standard is wrong, or the work drifted. Compare the most common variant with the SOP before changing either.',
      citations: ranked.flatMap(p => cite(p)),
      toVerify: ['Confirm the SOP version that adherence is measured against'],
      confidence: 0.82,
    }
  }

  if (lower.includes('variant')) {
    const ranked = [...visible].sort((a, b) => b.variants.length - a.variants.length).slice(0, 3)
    const first = ranked[0]
    if (!first) return fallback(id, q, processes, opportunities)
    return {
      id, question: q, intent: 'variants',
      headline: `${first.name} has the widest variant spread`,
      body: ranked.map(p => `${p.name}: ${p.variants.length} variants, ${fmt.percent(p.reworkRate)} rework, ${fmt.minutes(p.cycleMinutes)} median cycle.`).join('\n')
        + '\n\nVariation is the standard-work signal: pick the variant with the lowest rework, document it, and retire the rest with the owners.',
      citations: ranked.flatMap(p => cite(p)),
      toVerify: ['Variant labels are KYP.ai generated; confirm they mean what the team calls them.'],
      confidence: 0.8,
    }
  }

  if (lower.includes('stale') || lower.includes('fresh') || lower.includes('changed')) {
    const sorted = [...processes].sort((a, b) => b.staleDays - a.staleDays)
    const stale = sorted.filter(p => p.staleDays > 14)
    return {
      id, question: q, intent: 'freshness',
      headline: stale.length ? `${stale.length} map${stale.length === 1 ? '' : 's'} no longer match the latest discovery` : 'All maps match the latest discovery',
      body: sorted.slice(0, 4).map(p => `${p.name}: last evidence ${p.staleDays} day${p.staleDays === 1 ? '' : 's'} old.`).join('\n'),
      citations: sorted.slice(0, 4).flatMap(p => cite(p)),
      toVerify: [], confidence: 0.9,
    }
  }

  if (lower.includes('save') || lower.includes('saving') || lower.includes('worth') || lower.includes('automate')) {
    const named = processes.find(p => lower.includes(p.name.toLowerCase()))
    const candidates = opportunities
      .filter(o => !named || o.processId === named.id)
      .sort((a, b) => b.hours - a.hours)
    const best = candidates[0]
    if (!best) return fallback(id, q, processes, opportunities)
    return {
      id, question: q, intent: 'opportunity',
      headline: `${best.title}: about ${fmt.hoursPerYear(best.hours)} of effort`,
      body: `${best.title} is the largest opportunity in that scope at ${fmt.hoursPerYear(best.hours)}.\nRoute: ${best.route} — estimate only.\nConfidence in the estimate: ${fmt.percent(best.confidence)}.\n\nThis is an estimate, not a validated saving. It becomes a claim only after an owner commits it and before/after evidence validates it.`,
      citations: [
        { kind: 'kg', ref: best.kgId, label: best.title },
        { kind: 'kyp', ref: best.processId, label: best.processName },
      ],
      toVerify: ['Estimated saving — needs an owner and before/after evidence', 'Confirm the effort estimate with the process owner'],
      confidence: best.confidence,
    }
  }

  return fallback(id, q, processes, opportunities)
}

function fallback(id: string, question: string, processes: Process[], opportunities: Opportunity[]): Answer {
  const total = processes.reduce((sum, p) => sum + p.annualHours, 0)
  const best = [...opportunities].sort((a, b) => b.hours - a.hours)[0]
  return {
    id, question, intent: 'fallback',
    headline: 'I can answer that from the graph, but not this phrasing',
    body: `ProcessLink holds ${processes.length} discovered processes covering ${fmt.hoursPerYear(total)}.` +
      (best ? ` The largest opportunity is ${best.title} at ${fmt.hoursPerYear(best.hours)} (estimate).` : '') +
      '\n\nTry asking about handoffs and rework, standard-work adherence, variants, a named process or freshness.',
    citations: best ? [{ kind: 'kg', ref: best.kgId, label: best.title }] : [],
    toVerify: best ? ['Savings are estimates until validated'] : [],
    confidence: 0.55,
  }
}
