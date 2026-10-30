import { useEffect, useState } from 'react'
import { useApp } from '../App'
import { Card, Chip, Note } from '../components/ui'
import { OsActivity } from '../components/OsActivity'
import { osGet, type DeckForgeDecks, type LiveMap, type LiveProjects, type LiveVision, type VisionRoadmap } from '../domain/osBridge'

const OS = (import.meta.env.VITE_FLIGHTDECK_URL as string | undefined) || 'http://127.0.0.1:4173'
const ATLAS = (import.meta.env.VITE_ATLAS_URL as string | undefined) || 'http://localhost:5173'
const PDF = (import.meta.env.VITE_PDF_STUDIO_URL as string | undefined) || 'http://127.0.0.1:4176'
const DECK = (import.meta.env.VITE_DECKFORGE_URL as string | undefined) || 'deckforge://'

const links = [
  { id: 'os', label: 'Flightdeck OS', detail: 'Workspace, project, Maps, Advantage, Vision and the app directory.', url: OS, tone: 'blue' as const },
  { id: 'maps', label: 'Maps / DiagramForge', detail: 'Process maps, shape comments and execution history.', url: `${OS}/console/apps/maps`, tone: 'green' as const },
  { id: 'atlas', label: 'Atlas', detail: 'Projects, portfolio context and OS workspace/project selection.', url: ATLAS, tone: 'purple' as const },
  { id: 'vision', label: 'Vision', detail: 'Strategy, goals and the owner projection.', url: `${OS}/console/vision?standalone=1`, tone: 'orange' as const },
  { id: 'pdf', label: 'PDF Studio', detail: 'Document review, annotations and approved outputs.', url: PDF, tone: 'red' as const },
  { id: 'deck', label: 'DeckForge', detail: 'Leadership briefs and decks from the same initiative brief.', url: DECK, tone: 'teal' as const },
]

export default function Suite() {
  const { hostWorkspace, hostProject } = useApp()
  const [update, setUpdate] = useState<{ status: string; latest?: string; url?: string; error?: string }>({ status: 'idle' })
  const [liveMaps, setLiveMaps] = useState<LiveMap[] | null>(null)
  const [liveVision, setLiveVision] = useState<LiveVision | null>(null)
  const [liveProjects, setLiveProjects] = useState<LiveProjects | null>(null)
  const [roadmap, setRoadmap] = useState<VisionRoadmap | null>(null)
  const [decks, setDecks] = useState<DeckForgeDecks | null>(null)
  const [health, setHealth] = useState<Record<string, 'checking' | 'up' | 'down'>>({})
  const [aiStatus, setAiStatus] = useState<{ ok: boolean; model?: string } | null>(null)
  useEffect(() => {
    void fetch('http://127.0.0.1:4183/health').then(async response => {
      if (!response.ok) throw new Error('not running')
      const data = await response.json() as { ok?: boolean; model?: string }
      setAiStatus({ ok: data.ok === true, model: data.model })
    }).catch(() => setAiStatus({ ok: false }))
    void Promise.all([
      osGet<LiveMap[]>('/api/apps/maps/maps'), osGet<LiveVision>('/api/vision/bootstrap'),
      osGet<LiveProjects>('/api/projects'), osGet<VisionRoadmap>('/api/vision/roadmap'),
      osGet<DeckForgeDecks>('/deckforge/api/apps/presentation-studio/decks'),
    ]).then(([maps, vision, projects, road, deckData]) => {
      setLiveMaps(maps); setLiveVision(vision); setLiveProjects(projects); setRoadmap(road); setDecks(deckData)
    })
  }, [])
  const check = async () => {
    setUpdate({ status: 'checking' })
    try {
      const response = await fetch('https://api.github.com/repos/pallefar/ProcessLink/releases/latest', { headers: { accept: 'application/vnd.github+json' } })
      if (!response.ok) throw new Error(`GitHub HTTP ${response.status}`)
      const data = await response.json() as { tag_name: string; html_url: string }
      const latest = data.tag_name.replace(/^v/i, '')
      const current = '0.1.35'
      const newer = latest.localeCompare(current, undefined, { numeric: true }) > 0
      setUpdate({ status: newer ? 'available' : 'current', latest, url: data.html_url })
    } catch (error) {
      setUpdate({ status: 'error', error: error instanceof Error ? error.message : 'Update check failed' })
    }
  }
  return (
    <div className="suite-page">
      <div className="page-head">
        <div>
          <h2 className="page-title">OS suite</h2>
          <p className="page-sub">The apps ProcessLink shares context with. Links are configured per environment; nothing is written back.</p>
        </div>
        <div className="row-meta">
          <Chip tone={hostWorkspace ? 'green' : undefined}>{hostWorkspace ? `Host · ${hostWorkspace}` : 'UAT context'}</Chip>
          {hostProject && <Chip>{hostProject}</Chip>}
        </div>
      </div>

      <div className="suite-grid">
        {links.map(link => (
          <Card key={link.id} title={link.label} subtitle={link.detail} glyph="↗">
            <div className="row-meta">
              <Chip tone={link.tone}>{new URL(link.url).protocol.replace(':', '')}</Chip>
              <span className="subtle mono" style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{link.url}</span>
            </div>
            <div className="row-meta">
              <a className="btn small" href={link.url} target="_blank" rel="noreferrer">Open {link.label}</a>
              {link.url.startsWith('http') && <button className="btn small" onClick={async () => {
                setHealth(current => ({ ...current, [link.id]: 'checking' }))
                try {
                  await fetch(link.url, { mode: 'no-cors', cache: 'no-store' })
                  setHealth(current => ({ ...current, [link.id]: 'up' }))
                } catch {
                  setHealth(current => ({ ...current, [link.id]: 'down' }))
                }
              }}>{health[link.id] === 'checking' ? 'Checking…' : 'Check'}</button>}
              {health[link.id] === 'up' && <Chip tone="green">Up</Chip>}
              {health[link.id] === 'down' && <Chip tone="red">Down</Chip>}
            </div>
          </Card>
        ))}
      </div>

      <Card title="Live OS context" subtitle="Read from the same-origin OS session when ProcessLink is mounted at /processlink/." glyph="◉">
        <div className="grid three" style={{ gap: 12 }}>
          <div><Chip tone={liveMaps ? 'green' : undefined}>{liveMaps ? `${liveMaps.length} maps` : 'Maps unavailable'}</Chip><div className="tiny" style={{ marginTop: 4 }}>{liveMaps?.[0]?.label ?? 'No OS map visible'}</div></div>
          <div><Chip tone={liveVision?.strategy ? 'purple' : undefined}>{liveVision?.strategy ? 'Vision connected' : 'Vision unavailable'}</Chip><div className="tiny" style={{ marginTop: 4 }}>{liveVision?.strategy?.body?.title ?? 'No strategy visible'}</div></div>
          <div><Chip tone="blue">Session</Chip><div className="tiny" style={{ marginTop: 4 }}>{hostWorkspace || 'No OS host context'} · {hostProject || 'no project'}</div></div>
          <div><Chip tone={aiStatus?.ok ? 'green' : undefined}>AI sidecar</Chip><div className="tiny" style={{ marginTop: 4 }}>{aiStatus?.ok ? aiStatus.model : 'Not running on :4183'}</div></div>
        </div>
        {liveMaps && liveMaps.length > 0 && (
          <div style={{ marginTop: 10 }}>
            {liveMaps.slice(0, 3).map(map => (
              <div className="row-meta" key={map.id} style={{ justifyContent: 'space-between', padding: '3px 0' }}>
                <span>{map.label}</span>
                <a className="btn small" href={`/console/apps/maps?map=${encodeURIComponent(map.id)}`} target="_blank" rel="noreferrer">Open map</a>
              </div>
            ))}
          </div>
        )}
      </Card>

      <div className="grid two wide">
        <Card title="Atlas projects" subtitle="OS workspace/project registry, read through the same session." glyph="⌘">
          <div className="row-meta">
            <Chip tone={liveProjects ? 'green' : undefined}>{liveProjects ? `${liveProjects.projects.length} projects` : 'Unavailable'}</Chip>
            {liveProjects && <Chip>{liveProjects.workspaceId}</Chip>}
          </div>
          {liveProjects?.projects.slice(0, 5).map(project => (
            <div className="row-meta" key={project.id} style={{ justifyContent: 'space-between', padding: '3px 0' }}>
              <span>{project.label}</span><span className="tiny">{project.isDefault ? 'default' : project.id}</span>
            </div>
          ))}
          {liveProjects && <a className="btn small" href={ATLAS} target="_blank" rel="noreferrer">Open Atlas projects</a>}
        </Card>
        <Card title="DeckForge decks" subtitle="Live Presentation Studio decks from the local app." glyph="▤">
          <div className="row-meta"><Chip tone={decks ? 'green' : undefined}>{decks ? `${decks.items.length} decks` : 'Unavailable'}</Chip></div>
          {decks?.items.slice(0, 4).map(deck => (
            <div className="row-meta" key={deck.deckId} style={{ justifyContent: 'space-between', padding: '3px 0' }}>
              <span>{deck.title}</span><span className="tiny">rev {deck.revision}</span>
            </div>
          ))}
          <a className="btn small" href="http://127.0.0.1:4179/" target="_blank" rel="noreferrer">Open DeckForge</a>
        </Card>
        <Card title="Vision roadmap" subtitle="Goals and roadmap rows from the OS Vision projection." glyph="◇">
          <div className="row-meta">
            <Chip tone={roadmap ? 'purple' : undefined}>{roadmap ? `${roadmap.records.length} items` : 'Unavailable'}</Chip>
            {liveVision?.strategy?.body?.title && <Chip>{liveVision.strategy.body.title}</Chip>}
          </div>
          {roadmap?.records.slice(0, 5).map(item => (
            <div className="row-meta" key={item.id} style={{ justifyContent: 'space-between', padding: '3px 0' }}>
              <span>{item.body?.title ?? item.id}</span><span className="tiny">{item.body?.stage ?? item.body?.status ?? ''}</span>
            </div>
          ))}
          <a className="btn small" href="/console/vision?standalone=1" target="_blank" rel="noreferrer">Open Vision</a>
        </Card>
      </div>

      <OsActivity />

      <Card title="ProcessLink updates" subtitle="Reads the public GitHub release feed; never installs silently." glyph="↓">
        <div className="row-meta">
          <Chip>Installed 0.1.35</Chip>
          {update.latest && <Chip tone="blue">Latest {update.latest}</Chip>}
          {update.status === 'current' && <Chip tone="green">Up to date</Chip>}
          {update.status === 'available' && <Chip tone="orange">Update available</Chip>}
          <button className="btn small" onClick={check} disabled={update.status === 'checking'}>{update.status === 'checking' ? 'Checking…' : 'Check for updates'}</button>
          {update.url && <a className="btn small" href={update.url} target="_blank" rel="noreferrer">Release notes</a>}
        </div>
        {update.error && <p className="subtle" style={{ color: 'var(--orange)' }}>{update.error}</p>}
      </Card>

      <Card title="Handoff contracts" subtitle="Files and links that cross the app boundary." glyph="⇄">
        <ul className="suite-contracts">
          <li><strong>Maps/DiagramForge</strong> — live map documents and contract-flow execution history are read-only; annotations stay local.</li>
          <li><strong>Atlas</strong> — OS workspace/project context and project list; no Atlas writes.</li>
          <li><strong>Vision</strong> — strategy/KPI context; no write-back.</li>
          <li><strong>PDF Studio</strong> — feedback and approved documents are exported as an annotation package for human review.</li>
          <li><strong>DeckForge</strong> — an initiative brief is exported as Markdown/JSON; generated decks return as files, not live state.</li>
        </ul>
      </Card>

      <Note>For the web app mounted inside the OS, append <span className="mono">?workspace=&lt;id&gt;&amp;project=&lt;id&gt;</span>. The sidebar reads that host context and never invents a different workspace.</Note>
    </div>
  )
}
