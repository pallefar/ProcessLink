import { useEffect, useState } from 'react'
import { Card, Chip, PageHead } from '../components/ui'

interface Check { id: string; label: string; status: 'idle' | 'running' | 'up' | 'down'; detail: string; ms: number }

const CHECKS: Array<{ id: string; label: string; run: () => Promise<string> }> = [
  {
    id: 'os', label: 'Flightdeck OS health',
    run: async () => {
      const response = await fetch('/api/health/live', { credentials: 'same-origin' })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      return 'OS process is live'
    },
  },
  {
    id: 'session', label: 'OS session',
    run: async () => {
      const response = await fetch('/api/projects', { credentials: 'same-origin' })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json() as { workspaceId: string; projects: unknown[] }
      return `${data.workspaceId} · ${data.projects.length} projects`
    },
  },
  {
    id: 'maps', label: 'Maps / DiagramForge',
    run: async () => {
      const response = await fetch('/api/apps/maps/maps', { credentials: 'same-origin' })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json() as unknown[]
      return `${data.length} live maps`
    },
  },
  {
    id: 'vision', label: 'Vision',
    run: async () => {
      const response = await fetch('/api/vision/roadmap', { credentials: 'same-origin' })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json() as { records: unknown[] }
      return `${data.records.length} roadmap items`
    },
  },
  {
    id: 'deckforge', label: 'DeckForge',
    run: async () => {
      const response = await fetch('/deckforge/api/apps/presentation-studio/decks', { credentials: 'same-origin' })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json() as { items: unknown[] }
      return `${data.items.length} decks`
    },
  },
  {
    id: 'ai', label: 'transformers.js sidecar',
    run: async () => {
      const response = await fetch('http://127.0.0.1:4183/health')
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json() as { model?: string }
      return data.model ?? 'healthy'
    },
  },
]

export default function Diagnostics() {
  const [checks, setChecks] = useState<Check[]>(CHECKS.map(item => ({ id: item.id, label: item.label, status: 'idle', detail: 'Not run', ms: 0 })))
  const [running, setRunning] = useState(false)

  const run = async () => {
    setRunning(true)
    for (const check of CHECKS) {
      setChecks(current => current.map(item => item.id === check.id ? { ...item, status: 'running' } : item))
      const started = performance.now()
      try {
        const detail = await check.run()
        setChecks(current => current.map(item => item.id === check.id ? { ...item, status: 'up', detail, ms: Math.round(performance.now() - started) } : item))
      } catch (error) {
        setChecks(current => current.map(item => item.id === check.id ? { ...item, status: 'down', detail: error instanceof Error ? error.message : 'Failed', ms: Math.round(performance.now() - started) } : item))
      }
    }
    setRunning(false)
  }

  useEffect(() => { void run() }, [])

  return (
    <div className="diagnostics-page">
      <PageHead title="Diagnostics" subtitle="Live checks through the same-origin OS session. No writes." />
      <div className="row-meta">
        <Chip tone={checks.every(check => check.status === 'up') ? 'green' : checks.some(check => check.status === 'down') ? 'red' : undefined}>
          {checks.filter(check => check.status === 'up').length}/{checks.length} up
        </Chip>
        <button className="btn primary" onClick={run} disabled={running}>{running ? 'Running…' : 'Run checks again'}</button>
      </div>
      <Card title="Integration checks" subtitle="OS, Maps, Vision, DeckForge and the local AI sidecar." glyph="◉">
        {checks.map(check => (
          <div className="diag-row" key={check.id}>
            <div>
              <strong>{check.label}</strong>
              <div className="tiny">{check.detail}</div>
            </div>
            <div className="row-meta">
              {check.ms > 0 && <span className="tiny">{check.ms} ms</span>}
              <Chip tone={check.status === 'up' ? 'green' : check.status === 'down' ? 'red' : check.status === 'running' ? 'orange' : undefined}>
                {check.status === 'up' ? 'Up' : check.status === 'down' ? 'Down' : check.status === 'running' ? 'Running' : 'Not run'}
              </Chip>
            </div>
          </div>
        ))}
      </Card>
    </div>
  )
}
