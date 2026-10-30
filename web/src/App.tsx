import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import { loadOsState, saveOsState } from './domain/osState'
import { Shell } from './Shell'
import {
  AUDIT, BLOCKS, GOVERNANCE, INITIATIVES, KG_EDGES, KG_NODES, MEETINGS, NOW, OPPORTUNITIES, POLICY, PROCESSES,
} from './domain/data'
import { evaluate, fmt, recommendMethod, scanPII } from './domain/rules'
import { answer as answerQuestion, SUGGESTIONS } from './domain/ask'
import { MEETING_LABEL } from './domain/labels'
import type {
  Answer, AuditEntry, BlockKind, GovernanceItem, Initiative, KGEdge, KGNode, Meeting,
  Feedback, FeedbackKind, MeetingBlock, MeetingKind, Opportunity, PrivacyPolicy,
} from './domain/types'

export type Page =
  | 'overview' | 'strategy' | 'discoveries' | 'opportunities' | 'maps' | 'osMaps' | 'meetings' | 'mining'
  | 'graph' | 'improvements' | 'feedback' | 'agent' | 'suite' | 'diagnostics' | 'ask' | 'governance'

export const NAV: Array<{ id: Page; label: string; group: string; icon: string }> = [
  { id: 'overview', label: 'Overview', group: 'Work', icon: 'overview' },
  { id: 'strategy', label: 'Strategy', group: 'Work', icon: 'target' },
  { id: 'discoveries', label: 'Discoveries', group: 'Work', icon: 'discoveries' },
  { id: 'opportunities', label: 'Opportunities', group: 'Work', icon: 'opportunities' },
  { id: 'maps', label: 'Maps', group: 'Work', icon: 'maps' },
  { id: 'osMaps', label: 'OS maps', group: 'Work', icon: 'map' },
  { id: 'meetings', label: 'Meetings', group: 'Work', icon: 'meetings' },
  { id: 'mining', label: 'Mining', group: 'Work', icon: 'mining' },
  { id: 'improvements', label: 'Improvements', group: 'Improve', icon: 'improvements' },
  { id: 'feedback', label: 'Feedback', group: 'Improve', icon: 'comment' },
  { id: 'agent', label: 'Capture agent', group: 'Trust', icon: 'desktop' },
  { id: 'suite', label: 'OS suite', group: 'Trust', icon: 'link' },
  { id: 'diagnostics', label: 'Diagnostics', group: 'Trust', icon: 'activity' },
  { id: 'ask', label: 'Ask', group: 'Improve', icon: 'ask' },
  { id: 'graph', label: 'Knowledge Graph', group: 'Trust', icon: 'graph' },
  { id: 'governance', label: 'Governance', group: 'Trust', icon: 'governance' },
]

interface Toast { id: number; title: string; detail?: string; warning?: boolean }

interface AppValue {
  page: Page
  navigate: (page: Page) => void
  processes: typeof PROCESSES
  opportunities: Opportunity[]
  initiatives: Initiative[]
  feedback: Feedback[]
  addFeedback: (input: { kind: FeedbackKind; subjectId: string; subjectLabel: string; body: string; parentId?: string; page?: number; documentId?: string }) => boolean
  setFeedbackResolved: (id: string, resolved: boolean) => void
  nodes: KGNode[]
  edges: KGEdge[]
  meetings: Meeting[]
  blocks: MeetingBlock[]
  selectedMeeting: string
  selectMeeting: (id: string) => void
  createMeeting: (kind: MeetingKind) => void
  updateMeeting: (id: string, patch: Partial<Meeting>) => void
  addMeetingBlock: (meetingId: string, kind: BlockKind, after?: number) => void
  updateBlock: (id: string, patch: Partial<MeetingBlock>) => void
  deleteBlock: (id: string) => void
  toggleBlock: (id: string) => void
  linkMeeting: (id: string, patch: { processId?: string; initiativeId?: string }) => void
  promoteAction: (blockId: string) => void
  governance: GovernanceItem[]
  audit: AuditEntry[]
  answers: Answer[]
  policy: PrivacyPolicy
  setPolicy: (policy: PrivacyPolicy) => void
  hostWorkspace: string
  hostProject: string
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

export default function ProcessLink({ embedded = false }: { embedded?: boolean } = {}) {
  const [page, setPage] = useState<Page>(() => {
    if (!embedded) return pageFromHash()
    const requested = new URLSearchParams(window.location.search).get('p')
    return requested && NAV.some(item => item.id === requested) ? requested as Page : 'overview'
  })
  const [opportunities, setOpportunities] = useState<Opportunity[]>(OPPORTUNITIES)
  const [initiatives, setInitiatives] = useState<Initiative[]>(INITIATIVES)
  const [nodes, setNodes] = useState<KGNode[]>(KG_NODES)
  const [edges, setEdges] = useState<KGEdge[]>(KG_EDGES)
  const [meetings, setMeetings] = useState<Meeting[]>(MEETINGS)
  const [blocks, setBlocks] = useState<MeetingBlock[]>(BLOCKS)
  const feedbackHydratedRef = useRef(false)
  const [feedback, setFeedback] = useState<Feedback[]>(() => {
    try {
      const stored = window.localStorage.getItem('processlink.feedback.v1')
      if (stored) return JSON.parse(stored) as Feedback[]
    } catch { /* first run or private mode */ }
    return [
      { id: 'fb-web-1', kind: 'process', subjectId: 'p-order', subjectLabel: 'Order intake & validation', parentId: '', body: 'Should the second pricing check be sampled rather than removed? @Ops Excellence Lead', author: 'CI Manager (role)', createdAt: new Date(Date.now() - 2 * 86400000).toISOString(), resolved: false, mentions: ['@Ops'] },
      { id: 'fb-web-2', kind: 'map', subjectId: 'p-triage', subjectLabel: 'Customer case triage — as-is', parentId: '', body: 'The resolver handoff looks longer than the standard. Confirm on the next huddle?', author: 'Order Desk Lead', createdAt: new Date(Date.now() - 86400000).toISOString(), resolved: false, mentions: [] },
    ]
  })
  useEffect(() => {
    void loadOsState<Feedback[]>('feedback.v1').then(remote => {
      if (Array.isArray(remote)) setFeedback(remote)
      feedbackHydratedRef.current = true
    })
  }, [])
  useEffect(() => {
    try { window.localStorage.setItem('processlink.feedback.v1', JSON.stringify(feedback)) } catch { /* ignore */ }
    if (feedbackHydratedRef.current) void saveOsState('feedback.v1', feedback)
  }, [feedback])
  const [governance, setGovernance] = useState<GovernanceItem[]>(GOVERNANCE)
  const [audit, setAudit] = useState<AuditEntry[]>(AUDIT)
  const [answers, setAnswers] = useState<Answer[]>(() => {
    const question = new URLSearchParams(window.location.search).get('q')
    return question ? [answerQuestion(question, PROCESSES, OPPORTUNITIES, MEETINGS, BLOCKS)] : []
  })
  const hostParams = new URLSearchParams(window.location.search)
  const hostWorkspace = hostParams.get('workspace') || (() => { try { return localStorage.getItem('flightdeck.tenantWorkspace') || '' } catch { return '' } })()
  const hostProject = hostParams.get('project') || (() => { try { return localStorage.getItem('flightdeck.project') || '' } catch { return '' } })()
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
  const [selectedMeeting, selectMeeting] = useState(MEETINGS[0]?.id ?? '')

  useEffect(() => {
    if (embedded) return
    const onHash = () => setPage(pageFromHash())
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [embedded])

  useEffect(() => {
    if (embedded) return
    if (window.location.hash !== `#/${page}`) {
      window.history.replaceState(null, '', `#/${page}`)
    }
  }, [page, embedded])

  useEffect(() => {
    if (theme === 'auto') delete document.documentElement.dataset.theme
    else document.documentElement.dataset.theme = theme
  }, [theme])

  useEffect(() => {
    if (!toast) return
    const timer = window.setTimeout(() => setToast(null), 3800)
    return () => window.clearTimeout(timer)
  }, [toast])

  const addFeedback = useCallback((input: { kind: FeedbackKind; subjectId: string; subjectLabel: string; body: string; parentId?: string; page?: number; documentId?: string }) => {
    const trimmed = input.body.trim()
    if (!trimmed) return false
    const mentions = trimmed.match(/@[A-Za-z0-9._-]+/g) ?? []
    const record: Feedback = {
      id: `fb-${Date.now()}-${Math.random().toString(16).slice(2)}`,
      kind: input.kind, subjectId: input.subjectId, subjectLabel: input.subjectLabel,
      parentId: input.parentId ?? '', body: trimmed, author: 'CI Manager (role)',
      createdAt: new Date().toISOString(), resolved: false, mentions: [...new Set(mentions)],
      page: input.page, documentId: input.documentId,
    }
    setFeedback(current => [record, ...current])
    return true
  }, [])
  const setFeedbackResolved = useCallback((id: string, resolved: boolean) => {
    setFeedback(current => current.map(item => item.id === id ? { ...item, resolved } : item))
  }, [])

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
    if (embedded) {
      const url = new URL(window.location.href)
      url.searchParams.set('p', next)
      window.history.pushState({ processlinkPage: next }, '', url)
    }
    window.scrollTo({ top: 0 })
  }, [embedded])

  useEffect(() => {
    if (!embedded) return
    const onPop = () => {
      const requested = new URLSearchParams(window.location.search).get('p')
      setPage(requested && NAV.some(item => item.id === requested) ? requested as Page : 'overview')
    }
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [embedded])

  const upsertNode = useCallback((node: KGNode) => {
    setNodes(current => current.some(n => n.id === node.id)
      ? current.map(n => n.id === node.id ? { ...n, ...node } : n)
      : [...current, node])
  }, [])

  const upsertEdge = useCallback((edge: KGEdge) => {
    setEdges(current => current.some(e => e.from === edge.from && e.predicate === edge.predicate && e.to === edge.to)
      ? current
      : [...current, edge])
  }, [])

  const writeInitiative = useCallback((initiative: Initiative, opportunityId?: string) => {
    upsertNode({
      id: `kg-ini-${initiative.id}`, kind: 'initiative', name: initiative.title,
      confidence: 0.93, review: 'confirmed', source: 'ProcessLink TEOA layer',
      sourceId: initiative.id, validFrom: new Date().toISOString(), processId: initiative.processId,
    })
    upsertNode({
      id: `kg-savings-${initiative.id}`, kind: 'savingsRecord',
      name: `${Math.round(initiative.savingsHours)} h · Estimated`, confidence: 0.8,
      review: 'confirmed', source: 'ProcessLink value tracking', sourceId: initiative.id,
      validFrom: new Date().toISOString(), processId: initiative.processId,
    })
    if (opportunityId) {
      upsertEdge({ from: `kg-opp-${opportunityId}`, predicate: 'addressedBy', to: `kg-ini-${initiative.id}`, confidence: 0.9 })
    }
    upsertEdge({ from: `kg-ini-${initiative.id}`, predicate: 'realizesSavings', to: `kg-savings-${initiative.id}`, confidence: 0.9 })
  }, [upsertNode, upsertEdge])

  const createMeeting = useCallback((kind: MeetingKind) => {
    const id = `meet-${crypto.randomUUID().slice(0, 8)}`
    const meeting: Meeting = {
      id, title: `${MEETING_LABEL[kind]} · ${new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}`,
      kind, date: new Date().toISOString(), durationMinutes: kind === 'kaizen' ? 480 : 30,
      site: '', owner: 'CI Manager (role)', attendees: ['Process Owner', 'CI Manager'],
      processId: '', initiativeId: '', status: 'notes', summary: '', recurring: kind === 'dailyHuddle',
      cadence: kind === 'dailyHuddle' ? 'Daily' : '', kgId: `kg-meeting-${id}`,
    }
    setMeetings(current => [meeting, ...current])
    const created = templateBlocks(kind, id, 'CI Manager (role)')
    setBlocks(current => [...current, ...created])
    for (const item of created) {
      if (item.kind === 'decision' || item.kind === 'action') writeBlockNode(item, meeting)
    }
    upsertNode({ id: meeting.kgId, kind: 'meeting', name: meeting.title, confidence: 0.9,
      review: 'confirmed', source: 'ProcessLink meeting notes', sourceId: id,
      validFrom: meeting.date })
    selectMeeting(id)
    addAudit('meeting.created', meeting.title, `${MEETING_LABEL[kind]} note created.`)
    notify('Meeting note created', MEETING_LABEL[kind])
    navigate('meetings')
  }, [upsertNode, addAudit, notify, navigate])

  const updateMeeting = useCallback((id: string, patch: Partial<Meeting>) => {
    setMeetings(current => current.map(meeting => meeting.id === id ? { ...meeting, ...patch } : meeting))
  }, [])

  const writeBlockNode = useCallback((item: MeetingBlock, meeting: Meeting) => {
    upsertNode({
      id: `kg-${item.kind}-${item.id}`, kind: item.kind as 'decision' | 'action',
      name: item.text.slice(0, 90) || 'Untitled', confidence: 0.9, review: 'confirmed',
      source: 'ProcessLink meeting notes', sourceId: item.id, validFrom: meeting.date,
      processId: meeting.processId || undefined,
    })
    upsertEdge({ from: `kg-${item.kind}-${item.id}`, predicate: 'documentedIn', to: meeting.kgId, confidence: 0.95 })
    if (item.owner) {
      const roleId = `kg-role-${item.owner.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`
      upsertNode({ id: roleId, kind: 'role', name: item.owner, confidence: 0.88, review: 'confirmed',
        source: 'Meeting action owner', sourceId: item.id, validFrom: meeting.date })
      upsertEdge({ from: `kg-${item.kind}-${item.id}`, predicate: 'assignedTo', to: roleId, confidence: 0.9 })
    }
  }, [upsertNode, upsertEdge])

  const addMeetingBlock = useCallback((meetingId: string, kind: BlockKind, after?: number) => {
    const meeting = meetings.find(m => m.id === meetingId)
    if (!meeting) return
    const existing = blocks.filter(b => b.meetingId === meetingId)
    const order = after === undefined ? existing.length : after + 1
    const id = `blk-${crypto.randomUUID().slice(0, 8)}`
    const text = kind === 'heading' ? 'New section' : kind === 'decision' ? 'What did we decide?' : kind === 'action' ? 'What happens next?' : ''
    const item: MeetingBlock = {
      id, meetingId, order, kind, text, checked: false,
      owner: kind === 'action' ? meeting.owner : '',
      due: kind === 'action' ? new Date(Date.now() + 7 * 86_400_000).toISOString() : undefined,
    }
    setBlocks(current => [...current, item])
    if (kind === 'decision' || kind === 'action') writeBlockNode(item, meeting)
    setMeetings(current => current.map(m => m.id === meetingId ? { ...m, summary: m.summary } : m))
    addAudit('meeting.block.added', meeting.title, kind)
  }, [meetings, blocks, writeBlockNode, addAudit])

  const updateBlock = useCallback((id: string, patch: Partial<MeetingBlock>) => {
    setBlocks(current => current.map(item => item.id === id ? { ...item, ...patch } : item))
    const item = blocks.find(b => b.id === id)
    if (!item) return
    if (item.kind === 'decision' || item.kind === 'action') {
      const meeting = meetings.find(m => m.id === item.meetingId)
      if (meeting) {
        upsertNode({
          id: `kg-${item.kind}-${item.id}`, kind: item.kind,
          name: (patch.text ?? item.text).slice(0, 90) || 'Untitled',
          confidence: 0.9, review: 'confirmed', source: 'ProcessLink meeting notes',
          sourceId: item.id, validFrom: meeting.date, processId: meeting.processId || undefined,
        })
        const owner = patch.owner ?? item.owner
        if (owner) {
          const roleId = `kg-role-${owner.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`
          upsertNode({ id: roleId, kind: 'role', name: owner, confidence: 0.88, review: 'confirmed',
            source: 'Meeting action owner', sourceId: item.id, validFrom: meeting.date })
          upsertEdge({ from: `kg-${item.kind}-${item.id}`, predicate: 'assignedTo', to: roleId, confidence: 0.9 })
        }
      }
    }
  }, [blocks, meetings, upsertNode, upsertEdge])

  const deleteBlock = useCallback((id: string) => {
    setBlocks(current => current.filter(item => item.id !== id))
  }, [])

  const toggleBlock = useCallback((id: string) => {
    setBlocks(current => current.map(item => item.id === id ? { ...item, checked: !item.checked } : item))
  }, [])

  const linkMeeting = useCallback((id: string, patch: { processId?: string; initiativeId?: string }) => {
    setMeetings(current => current.map(meeting => {
      if (meeting.id !== id) return meeting
      const next = { ...meeting, ...patch }
      if (patch.processId) upsertEdge({ from: `kg-proc-${patch.processId}`, predicate: 'discussedIn', to: meeting.kgId, confidence: 0.85 })
      if (patch.initiativeId) upsertEdge({ from: `kg-ini-${patch.initiativeId}`, predicate: 'discussedIn', to: meeting.kgId, confidence: 0.85 })
      return next
    }))
    notify('Meeting linked', 'The page is connected in the graph.')
  }, [upsertEdge, notify])

  const promoteAction = useCallback((blockId: string) => {
    const item = blocks.find(b => b.id === blockId)
    if (!item) return
    const meeting = meetings.find(m => m.id === item.meetingId)
    if (!meeting) return
    const opportunity = item.linkedId ? opportunities.find(o => o.id === item.linkedId || o.kgId === item.linkedId) : undefined
    const process = PROCESSES.find(p => p.id === (meeting.processId || opportunity?.processId))
    const owner = item.owner || meeting.owner
    const initiative: Initiative = {
      id: `ini-${crypto.randomUUID().slice(0, 8)}`, title: item.text || `Action from ${meeting.title}`,
      opportunityId: opportunity?.id ?? '', processId: process?.id ?? '',
      processName: process?.name ?? meeting.title, site: process?.site ?? meeting.site,
      method: meeting.kind === 'kaizen' ? 'kaizen' : meeting.kind === 'a3Review' ? 'a3' : 'standardWork',
      owner: owner || 'Unassigned', stage: 'plan',
      due: item.due ?? new Date(Date.now() + 30 * 86_400_000).toISOString(),
      savingsHours: opportunity?.hours ?? 0, savingsStage: 'estimated', validatedBy: '', evidence: '',
      waste: opportunity?.waste ?? 'waiting',
      background: `From ${meeting.title} (${new Date(meeting.date).toLocaleDateString('en-GB')}).`,
      target: item.text, countermeasure: '', result: '',
    }
    setInitiatives(current => [initiative, ...current])
    if (opportunity) {
      setOpportunities(current => current.map(o => o.id === opportunity.id ? { ...o, status: 'promoted' } : o))
    }
    setBlocks(current => current.map(b => b.id === blockId ? { ...b, checked: true } : b))
    writeInitiative(initiative, opportunity?.id)
    addAudit('action.promoted', initiative.title, `From meeting ${meeting.id}.`)
    selectInitiative(initiative.id)
    notify('Action promoted', `${initiative.owner} · initiative created`)
    navigate('improvements')
  }, [blocks, meetings, opportunities, writeInitiative, addAudit, notify, navigate])

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
    writeInitiative(initiative, opportunity.id)
    selectInitiative(initiative.id)
    addAudit('initiative.created', initiative.title, `From ${opportunity.id}, ${fmt.hoursPerYear(initiative.savingsHours)} estimated.`)
    notify('Initiative started', `${initiative.owner} · ${fmt.hours(initiative.savingsHours)}`)
    navigate('improvements')
  }, [policy, notify, addAudit, navigate, writeInitiative])

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
    upsertNode({ id: `kg-savings-${initiative.id}`, kind: 'savingsRecord',
      name: `${Math.round(initiative.savingsHours)} h · Validated`, confidence: 1,
      review: 'confirmed', source: 'ProcessLink value tracking', sourceId: initiative.id,
      validFrom: new Date().toISOString(), note: `Validated by ${validator.trim()}.` })
    addAudit('savings.validated', initiative.title, `${fmt.hours(initiative.savingsHours)} validated by ${validator.trim()}.`)
    notify('Saving validated', `${fmt.hours(initiative.savingsHours)} · ${validator.trim()}`)
    return true
  }, [initiatives, notify, addAudit, upsertNode])

  const reviewNode = useCallback((nodeId: string, mergeInto?: string) => {
    setNodes(current => current.map(node => {
      if (node.id !== nodeId) return node
      if (mergeInto) {
        const target = current.find(n => n.id === mergeInto)
        return {
          ...node, review: 'rejected',
          note: `Merged into ${target?.name ?? mergeInto} by a human reviewer.`,
          validTo: new Date().toISOString(),
        }
      }
      return { ...node, review: 'confirmed' }
    }))
    if (mergeInto) {
      setEdges(current => current
        .map(edge => ({
          ...edge,
          from: edge.from === nodeId ? mergeInto : edge.from,
          to: edge.to === nodeId ? mergeInto : edge.to,
        }))
        .filter(edge => edge.from !== edge.to))
    }
    const node = nodes.find(n => n.id === nodeId)
    addAudit(mergeInto ? 'kg.merge.confirmed' : 'kg.node.confirmed', node?.name ?? nodeId, mergeInto ? 'Human confirmed the merge.' : 'Human confirmed the node.')
    notify('Review recorded', node?.name ?? nodeId)
  }, [nodes, addAudit, notify])

  const ask = useCallback((question: string) => {
    const trimmed = question.trim()
    if (!trimmed) return
    const scan = scanPII(trimmed)
    const result = answerQuestion(trimmed, PROCESSES, opportunities, meetings, blocks)
    if (scan.total > 0) {
      result.body += `\n\nPersonal-data patterns were found in the question and masked before analysis: ${scan.masked}.`
      result.toVerify.push('The question contained personal data; only the masked text was used.')
    }
    setAnswers(current => [...current, result])
    addAudit('ai.answer', 'Ask the process', `${result.citations.length} citations, provider ${policy.provider}.`)
  }, [opportunities, meetings, blocks, policy.provider, addAudit])

  const clearAsk = useCallback(() => setAnswers([]), [])

  const sync = useCallback(() => {
    addAudit('discovery.refreshed', 'In-house discovery',
      `${PROCESSES.length} processes, ${MEETINGS.length} meeting pages and ${BLOCKS.length} blocks read locally; no external connector.`)
    notify('Discovery refreshed', `${PROCESSES.length} processes · ${MEETINGS.length} meetings · local`)
  }, [addAudit, notify])

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
        `- Source: discovery ${o.processId} · KG ${o.kgId}`, '',
      ].join('\n')),
      '## Savings ledger', '',
      `- Estimated: ${fmt.hours(totals.estimated)}`,
      `- Committed: ${fmt.hours(totals.committed)}`,
      `- Validated: ${fmt.hours(totals.validated)}`, '',
      '> Estimates are not validated savings. Every figure traces to a discovery object or KG node.', '',
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
    page, navigate, processes: PROCESSES, opportunities, initiatives, feedback, addFeedback, setFeedbackResolved, nodes, edges, meetings, blocks,
    selectedMeeting, selectMeeting, createMeeting, updateMeeting, addMeetingBlock, updateBlock,
    deleteBlock, toggleBlock, linkMeeting, promoteAction,
    governance, audit, answers, policy, setPolicy, hostWorkspace, hostProject, toast, notify,
    selectedProcess, selectProcess, selectedOpportunity, selectOpportunity,
    selectedInitiative, selectInitiative, selectedNode, selectNode,
    promote, commitSaving, advanceInitiative, setGovernanceStatus, validateSaving, reviewNode, ask, clearAsk, sync, exportBrief,
    theme, setTheme, suggestions: SUGGESTIONS,
  }), [page, navigate, opportunities, initiatives, feedback, addFeedback, setFeedbackResolved, nodes, edges, meetings, blocks, governance, audit, answers, policy, hostWorkspace, hostProject,
    toast, notify, selectedProcess, selectedOpportunity, selectedInitiative, selectedNode, selectedMeeting,
    selectMeeting, createMeeting, updateMeeting, addMeetingBlock, updateBlock, deleteBlock, toggleBlock,
    linkMeeting, promoteAction,
    promote, commitSaving, advanceInitiative, setGovernanceStatus, validateSaving, reviewNode, ask, clearAsk, sync, exportBrief, theme])

  return (
    <AppContext.Provider value={value}>
      <Shell />
    </AppContext.Provider>
  )
}

function templateBlocks(kind: MeetingKind, meetingId: string, owner: string): MeetingBlock[] {
  const due = new Date(Date.now() + 7 * 86_400_000).toISOString()
  const rows: Array<[BlockKind, string, string?]> = (() => {
    switch (kind) {
      case 'dailyHuddle':
        return [['heading', 'Yesterday'], ['bullet', ''], ['heading', 'Today'], ['bullet', ''], ['heading', 'Blockers'], ['bullet', ''], ['decision', ''], ['action', '', owner]]
      case 'kaizen':
        return [['heading', 'Problem'], ['text', ''], ['heading', 'Target'], ['text', ''], ['heading', 'Countermeasures'], ['checklist', ''], ['decision', ''], ['action', '', owner]]
      case 'a3Review':
        return [['heading', 'Background'], ['text', ''], ['heading', 'Target vs actual'], ['text', ''], ['heading', 'Root cause'], ['text', ''], ['decision', ''], ['action', '', owner]]
      case 'leadership':
        return [['heading', 'Portfolio'], ['bullet', ''], ['heading', 'Decisions needed'], ['decision', ''], ['action', '', owner]]
      default:
        return [['heading', 'Context'], ['text', ''], ['heading', 'Notes'], ['bullet', ''], ['decision', ''], ['action', '', owner]]
    }
  })()
  return rows.map(([blockKind, text, blockOwner], index) => ({
    id: `${meetingId}-blk-${index}`, meetingId, order: index, kind: blockKind, text,
    checked: false, owner: blockOwner ?? '',
    due: blockKind === 'action' ? due : undefined,
  }))
}
