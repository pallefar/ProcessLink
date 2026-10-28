import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { Shell } from './Shell'
import {
  AUDIT, GOVERNANCE, INITIATIVES, KG_EDGES, KG_NODES, NOW, OPPORTUNITIES, POLICY, PROCESSES,
} from './domain/data'
import { evaluate, fmt, recommendMethod, routeFor, scanPII } from './domain/rules'
import { answer as answerQuestion, SUGGESTIONS } from './domain/ask'
import type {
  Answer, AuditEntry, GovernanceItem, Initiative, KGNode, Opportunity, PrivacyPolicy,
} from './domain/types'

export type Page =
  | 'overview' | 'discoveries' | 'opportunities' | 'maps'
  | 'graph' | 'improvements' | 'ask' | 'governance'

export const NAV: Array<{ id: Page; label: string; group: string; icon: string }> = [
  { id: 'overview', label: 'Overview', group: 'Work', icon: '▦' },
  { id: 'discoveries', label: 'Discoveries', group: 'Work', icon: '◉' },
  { id: 'opportunities', label: 'Opportunities', group: 'Work', icon: '◈' },
  { id: 'maps', label: 'Maps', group: 'Work', icon: '⌁' },
  { id: 'improvements', label: 'Improvements', group: 'Improve', icon: '⚑' },
  { id: 'ask', label: 'Ask', group: 'Improve', icon: '◍' },
  { id: 'graph', label: 'Knowledge Graph', group: 'Trust', icon: '⬡' },
  { id: 'governance', label: 'Governance', group: 'Trust', icon: '⛨' },
]

interface Toast { id: number; title: string; detail?: string; warning?: boolean }

interface AppValue {
  page: Page
  navigate: (page: Page) => void
  processes: typeof PROCESSES
  opportunities: Opportunity[]
  initiatives: Initiative[]
  nodes: KGNode[]
  edges: typeof KG_EDGES
  governance: GovernanceItem[]
  audit: AuditEntry[]
  answers: Answer[]
  policy: PrivacyPolicy
  setPolicy: (policy: PrivacyPolicy) => void
  toast: Toast | null
  notify: (title: string, detail?: string, warning?: boolean) => void
  selectedProcess: string
  selectProcess: (id: string) => void
  selectedOpportunity: string
  selectOpportunity: (id: string) => void
  selectedInitiative: string
  selectInitiative: (id: string) => void
  selectedNode: string
  selectNode: (id: string) => void
  promote: (opportunity: Opportunity) => void
  commitSaving: (initiativeId: string) => void
  advanceInitiative: (initiativeId: string) => void
  setGovernanceStatus: (id: string, status: GovernanceItem['status']) => void
  validateSaving: (initiativeId: string, validator: string, evidence: string) => boolean
  reviewNode: (nodeId: string, mergeInto?: string) => void
  ask: (question: string) => void
  clearAsk: () => void
  sync: () => void
  exportBrief: () => void
  theme: 'auto' | 'light' | 'dark'
  setTheme: (theme: 'auto' | 'light' | 'dark') => void
  suggestions: string[]
}

const AppContext = createContext<AppValue | null>(null)

export function useApp(): AppValue {
  const value = useContext(AppContext)
  if (!value) throw new Error('useApp must be used inside ProcessLink')
  return value
}

const pageFromHash = (): Page => {
  const raw = window.location.hash.replace(/^#\/?/, '')
  return NAV.some(item => item.id === raw) ? (raw as Page) : 'overview'
}

export default function ProcessLink() {
  const [page, setPage] = useState<Page>(pageFromHash)
  const [opportunities, setOpportunities] = useState<Opportunity[]>(OPPORTUNITIES)
  const [initiatives, setInitiatives] = useState<Initiative[]>(INITIATIVES)
  const [nodes, setNodes] = useState<KGNode[]>(KG_NODES)
  const [governance, setGovernance] = useState<GovernanceItem[]>(GOVERNANCE)
  const [audit, setAudit] = useState<AuditEntry[]>(AUDIT)
  const [answers, setAnswers] = useState<Answer[]>(() => {
    const question = new URLSearchParams(window.location.search).get('q')
    return question ? [answerQuestion(question, PROCESSES, OPPORTUNITIES)] : []
  })
  const [policy, setPolicy] = useState<PrivacyPolicy>(POLICY)
  const [toast, setToast] = useState<Toast | null>(null)
  const [theme, setTheme] = useState<'auto' | 'light' | 'dark'>(() => {
    const value = new URLSearchParams(window.location.search).get('theme')
    return value === 'light' || value === 'dark' ? value : 'auto'
  })
  const [selectedProcess, selectProcess] = useState(PROCESSES[0]?.id ?? '')
  const [selectedOpportunity, selectOpportunity] = useState(OPPORTUNITIES[0]?.id ?? '')
  const [selectedInitiative, selectInitiative] = useState(INITIATIVES[0]?.id ?? '')
  const [selectedNode, selectNode] = useState('kg-app-sap-ecc')

  useEffect(() => {
    const onHash = () => setPage(pageFromHash())
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  useEffect(() => {
    if (window.location.hash !== `#/${page}`) {
      window.history.replaceState(null, '', `#/${page}`)
    }
  }, [page])

  useEffect(() => {
    if (theme === 'auto') delete document.documentElement.dataset.theme
    else document.documentElement.dataset.theme = theme
  }, [theme])

  useEffect(() => {
    if (!toast) return
    const timer = window.setTimeout(() => setToast(null), 3800)
    return () => window.clearTimeout(timer)
  }, [toast])

  const notify = useCallback((title: string, detail?: string, warning = false) => {
    setToast({ id: Date.now(), title, detail, warning })
  }, [])

  const addAudit = useCallback((action: string, subject: string, detail: string) => {
    setAudit(current => [{
      id: crypto.randomUUID(), at: new Date().toISOString(), actor: 'CI Manager (role)',
      action, subject, detail,
    }, ...current])
  }, [])

  const navigate = useCallback((next: Page) => {
    setPage(next)
    window.scrollTo({ top: 0 })
  }, [])

  const promote = useCallback((opportunity: Opportunity) => {
    const process = PROCESSES.find(p => p.id === opportunity.processId)
    if (process) {
      const decision = evaluate({
        groupSize: process.people, classification: process.classification,
        destination: 'knowledgeGraph', purpose: 'processImprovement', policy,
      })
      if (!decision.allowed) {
        notify('Blocked by the privacy guard', decision.reason, true)
        addAudit('opportunity.promotion.blocked', opportunity.title, decision.reason)
        return
      }
    }
    const initiative: Initiative = {
      id: `ini-${crypto.randomUUID().slice(0, 8)}`,
      title: opportunity.title, opportunityId: opportunity.id,
      processId: opportunity.processId, processName: opportunity.processName,
      site: opportunity.site, method: opportunity.method, owner: opportunity.owner,
      stage: 'plan', due: new Date(NOW.getTime() + 30 * 86_400_000).toISOString(),
      savingsHours: opportunity.hours, savingsStage: 'estimated', validatedBy: '',
      evidence: '', waste: opportunity.waste,
      background: `Mined from ${opportunity.processName}: ${fmt.hoursPerYear(opportunity.hours)} of effort, ${fmt.percent(opportunity.confidence)} confidence.`,
      target: 'Remove half of the mined waste without adding a control step.',
      countermeasure: recommendMethod(opportunity.waste, opportunity.route, opportunity.statutory).reason,
      result: '',
    }
    setInitiatives(current => [initiative, ...current])
    setOpportunities(current => current.map(o => o.id === opportunity.id ? { ...o, status: 'promoted' } : o))
    selectInitiative(initiative.id)
    addAudit('initiative.created', initiative.title, `From ${opportunity.id}, ${fmt.hoursPerYear(initiative.savingsHours)} estimated.`)
    notify('Initiative started', `${initiative.owner} · ${fmt.hours(initiative.savingsHours)}`)
    navigate('improvements')
  }, [policy, notify, addAudit, navigate])

  const commitSaving = useCallback((initiativeId: string) => {
    setInitiatives(current => current.map(initiative => {
      if (initiative.id !== initiativeId || initiative.savingsStage !== 'estimated') return initiative
      if (!initiative.owner) {
        notify('A commitment needs an owner', 'Assign an owner before committing the saving.', true)
        return initiative
      }
      return { ...initiative, savingsStage: 'committed' }
    }))
    addAudit('savings.committed', initiativeId, 'Saving committed with a named owner.')
    notify('Saving committed', 'Estimated → committed. Validation still needs evidence.')
  }, [notify, addAudit])

  const advanceInitiative = useCallback((initiativeId: string) => {
    setInitiatives(current => current.map(initiative => {
      if (initiative.id !== initiativeId) return initiative
      const next = initiative.stage === 'plan' ? 'do' : initiative.stage === 'do' ? 'check' : 'act'
      return { ...initiative, stage: next }
    }))
    const initiative = initiatives.find(i => i.id === initiativeId)
    addAudit('initiative.stage', initiative?.title ?? initiativeId, 'Stage advanced.')
    notify('Stage advanced', initiative?.title)
  }, [initiatives, addAudit, notify])

  const setGovernanceStatus = useCallback((id: string, status: GovernanceItem['status']) => {
    setGovernance(current => current.map(item => item.id === id ? { ...item, status } : item))
    const item = governance.find(g => g.id === id)
    addAudit(`governance.${status}`, item?.title ?? id, `Status changed to ${status}.`)
    notify('Checklist updated', item?.title ?? id)
  }, [governance, addAudit, notify])

  const validateSaving = useCallback((initiativeId: string, validator: string, evidence: string): boolean => {
    const initiative = initiatives.find(i => i.id === initiativeId)
    if (!initiative) return false
    if (initiative.savingsStage !== 'committed') {
      notify('Commit the saving first', 'Validation follows a commitment with a named owner.', true)
      return false
    }
    if (!validator.trim()) {
      notify('A human validator is required', 'Name the person or role who checked the evidence.', true)
      return false
    }
    if (evidence.trim().length < 12) {
      notify('Before/after evidence is required', 'Describe the baseline, the after measurement and the period.', true)
      return false
    }
    setInitiatives(current => current.map(i => i.id === initiativeId
      ? { ...i, savingsStage: 'validated', validatedBy: validator.trim(), evidence: evidence.trim() }
      : i))
    addAudit('savings.validated', initiative.title, `${fmt.hours(initiative.savingsHours)} validated by ${validator.trim()}.`)
    notify('Saving validated', `${fmt.hours(initiative.savingsHours)} · ${validator.trim()}`)
    return true
  }, [initiatives, notify, addAudit])

  const reviewNode = useCallback((nodeId: string, mergeInto?: string) => {
    setNodes(current => current.map(node => {
      if (node.id !== nodeId) return node
      if (mergeInto) {
        const target = current.find(n => n.id === mergeInto)
        return {
          ...node, review: 'rejected',
          note: `Merged into ${target?.name ?? mergeInto} by a human reviewer.`,
        }
      }
      return { ...node, review: 'confirmed' }
    }))
    const node = nodes.find(n => n.id === nodeId)
    addAudit(mergeInto ? 'kg.merge.confirmed' : 'kg.node.confirmed', node?.name ?? nodeId, mergeInto ? 'Human confirmed the merge.' : 'Human confirmed the node.')
    notify('Review recorded', node?.name ?? nodeId)
  }, [nodes, addAudit, notify])

  const ask = useCallback((question: string) => {
    const trimmed = question.trim()
    if (!trimmed) return
    const scan = scanPII(trimmed)
    const result = answerQuestion(trimmed, PROCESSES, opportunities)
    if (scan.total > 0) {
      result.body += `\n\nPersonal-data patterns were found in the question and masked before analysis: ${scan.masked}.`
      result.toVerify.push('The question contained personal data; only the masked text was used.')
    }
    setAnswers(current => [...current, result])
    addAudit('ai.answer', 'Ask the process', `${result.citations.length} citations, provider ${policy.provider}.`)
  }, [opportunities, policy.provider, addAudit])

  const clearAsk = useCallback(() => setAnswers([]), [])

  const sync = useCallback(() => {
    const existing = opportunities.find(o => o.id === 'opp-sync-password')
    if (existing) {
      notify('Sync complete', 'No new opportunities in this window.')
      return
    }
    const base = {
      id: 'opp-sync-password', title: 'Deflect password-reset cases to self-service',
      processId: 'p-triage', waste: 'unusedTalent' as const, hours: 310, errorReduction: 6,
      effortWeeks: 6, risk: 3, alignment: 3, automation: 0.75, confidence: 0.81,
      statutory: false, status: 'new' as const, owner: 'Customer Care Lead',
      rationale: '31% of portal cases are password resets. Each takes 11 minutes of resolver time.',
    }
    const route = routeFor(base)
    const created: Opportunity = {
      ...base,
      processName: 'Customer case triage', site: 'Manila',
      route, method: recommendMethod(base.waste, route, false).method,
      kgId: 'kg-opp-opp-sync-password',
    }
    setOpportunities(current => [created, ...current])
    addAudit('sync.completed', 'KYP.ai sandbox', '341 objects fetched, 1 new opportunity, 2 skipped by policy.')
    notify('Sync complete', '1 new opportunity from KYP.ai.')
  }, [opportunities, notify, addAudit])

  const exportBrief = useCallback(() => {
    const ranked = [...opportunities].sort((a, b) => b.hours - a.hours).slice(0, 5)
    const totals = {
      estimated: initiatives.filter(i => i.savingsStage === 'estimated').reduce((sum, i) => sum + i.savingsHours, 0),
      committed: initiatives.filter(i => i.savingsStage === 'committed').reduce((sum, i) => sum + i.savingsHours, 0),
      validated: initiatives.filter(i => i.savingsStage === 'validated').reduce((sum, i) => sum + i.savingsHours, 0),
    }
    const lines = [
      '# ProcessLink review brief', '',
      `Generated ${fmt.day(new Date().toISOString())} · purpose: process improvement · data owner: ${policy.dataOwner}`, '',
      '## Priority opportunities', '',
      ...ranked.map(o => [
        `### ${o.title}`,
        `- Process: ${o.processName} · ${o.site}`,
        `- Route: ${o.route} · method: ${o.method}`,
        `- Estimate: ${fmt.hoursPerYear(o.hours)} · confidence ${fmt.percent(o.confidence)}`,
        `- Source: KYP.ai ${o.processId} · KG ${o.kgId}`, '',
      ].join('\n')),
      '## Savings ledger', '',
      `- Estimated: ${fmt.hours(totals.estimated)}`,
      `- Committed: ${fmt.hours(totals.committed)}`,
      `- Validated: ${fmt.hours(totals.validated)}`, '',
      '> Estimates are not validated savings. Every figure traces to a KYP.ai object or KG node.', '',
    ]
    const blob = new Blob([lines.join('\n')], { type: 'text/markdown' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = 'ProcessLink-review.md'
    link.click()
    URL.revokeObjectURL(url)
    addAudit('export.brief', 'ProcessLink-review.md', `${ranked.length} opportunities, ${initiatives.length} savings lines.`)
    notify('Brief exported', 'ProcessLink-review.md')
  }, [opportunities, initiatives, policy.dataOwner, addAudit, notify])

  const value = useMemo<AppValue>(() => ({
    page, navigate, processes: PROCESSES, opportunities, initiatives, nodes, edges: KG_EDGES,
    governance, audit, answers, policy, setPolicy, toast, notify,
    selectedProcess, selectProcess, selectedOpportunity, selectOpportunity,
    selectedInitiative, selectInitiative, selectedNode, selectNode,
    promote, commitSaving, advanceInitiative, setGovernanceStatus, validateSaving, reviewNode, ask, clearAsk, sync, exportBrief,
    theme, setTheme, suggestions: SUGGESTIONS,
  }), [page, navigate, opportunities, initiatives, nodes, governance, audit, answers, policy,
    toast, notify, selectedProcess, selectedOpportunity, selectedInitiative, selectedNode,
    promote, commitSaving, advanceInitiative, setGovernanceStatus, validateSaving, reviewNode, ask, clearAsk, sync, exportBrief, theme])

  return (
    <AppContext.Provider value={value}>
      <Shell />
    </AppContext.Provider>
  )
}

