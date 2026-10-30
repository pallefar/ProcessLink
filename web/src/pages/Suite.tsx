import { useState } from 'react'
import { useApp } from '../App'
import { Card, Chip, Note } from '../components/ui'

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
  const check = async () => {
    setUpdate({ status: 'checking' })
    try {
      const response = await fetch('https://api.github.com/repos/pallefar/ProcessLink/releases/latest', { headers: { accept: 'application/vnd.github+json' } })
      if (!response.ok) throw new Error(`GitHub HTTP ${response.status}`)
      const data = await response.json() as { tag_name: string; html_url: string }
      const latest = data.tag_name.replace(/^v/i, '')
      const current = '0.1.21'
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
            <a className="btn small" href={link.url} target="_blank" rel="noreferrer">Open {link.label}</a>
          </Card>
        ))}
      </div>

      <Card title="ProcessLink updates" subtitle="Reads the public GitHub release feed; never installs silently." glyph="↓">
        <div className="row-meta">
          <Chip>Installed 0.1.21</Chip>
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
