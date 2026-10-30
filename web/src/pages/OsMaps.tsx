import { useEffect, useState } from 'react'
import { Card, Chip, Empty, KV, PageHead } from '../components/ui'
import { useApp } from '../App'
import { FeedbackPanel } from '../components/FeedbackPanel'
import { FeedbackButton } from '../components/FeedbackButton'
import { osGet, type LiveMap } from '../domain/osBridge'

interface MapNode { id: string; type: string; label: string; data?: { role?: string; description?: string; stepId?: string; statutory?: boolean; humanOnly?: boolean } }
interface MapDetail { schema: string; id: string; label: string; nodes: MapNode[]; edges: Array<{ id: string; source: string; target: string }> }
interface MapApproval { canApprove: boolean; blocked: string; approved: string | null; latestRelease: string | null; draftMatchesRelease: boolean | null; lastEditor?: string }
interface MapRelease { version?: string; id?: string; status?: string; createdAt?: string; createdBy?: string }

export default function OsMaps() {
  const { processes } = useApp()
  const [processId, setProcessId] = useState('')
  const [maps, setMaps] = useState<LiveMap[] | null>(null)
  const [selected, setSelected] = useState('')
  const [detail, setDetail] = useState<MapDetail | null>(null)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [mapSearch, setMapSearch] = useState('')
  const [approval, setApproval] = useState<MapApproval | null>(null)
  const [releases, setReleases] = useState<MapRelease[]>([])
  const [aiBusy, setAiBusy] = useState(false)
  const [aiError, setAiError] = useState('')
  const [aiMapping, setAiMapping] = useState<Record<string, { step: string; confidence: number }>>({})
  const [aiThreshold, setAiThreshold] = useState(0.35)

  useEffect(() => {
    void osGet<LiveMap[]>('/api/apps/maps/maps').then(value => {
      setMaps(value)
      if (value?.[0]) setSelected(value[0].id)
    })
  }, [])

  useEffect(() => {
    if (!selected) return
    setDetail(null); setError(''); setApproval(null); setReleases([])
    void osGet<MapDetail>(`/api/apps/maps/maps/${encodeURIComponent(selected)}`).then(value => {
      if (value) setDetail(value); else setError('The OS map could not be read with this session.')
    })
    void osGet<MapApproval>(`/api/apps/maps/maps/${encodeURIComponent(selected)}/approval`).then(setApproval)
    void osGet<{ releases: MapRelease[] }>(`/api/apps/maps/maps/${encodeURIComponent(selected)}/releases`).then(value => setReleases(value?.releases ?? []))
  }, [selected])

  const process = processes.find(item => item.id === processId) ?? processes[0]
  const normalization = (value: string) => value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()
  const mapLabels = (detail?.nodes.filter(node => node.type === 'step') ?? []).map(node => normalization(node.label))
  const processLabels = (process?.steps ?? []).map(step => normalization(step.name))
  const matched = processLabels.filter(label => mapLabels.some(mapLabel => mapLabel === label || mapLabel.includes(label) || label.includes(mapLabel)))
  const missing = processLabels.filter(label => !matched.includes(label))
  const extra = mapLabels.filter(label => !processLabels.some(processLabel => processLabel === label || processLabel.includes(label) || label.includes(processLabel)))
  const downloadMiningCSV = () => {
    if (!detail) return
    const rows = [['case_id', 'activity', 'timestamp', 'resource', 'application']]
    const base = Date.now()
    detail.nodes.filter(node => node.type === 'step').forEach((node, index) => {
      rows.push([`map-${detail.id}`, node.label, new Date(base + index * 60000).toISOString(), node.data?.role ?? '', 'DiagramForge'])
    })
    const blob = new Blob([rows.map(row => row.map(value => `"${String(value).replaceAll('"', '""')}"`).join(',')).join('\n')], { type: 'text/csv' })
    const url = URL.createObjectURL(blob); const link = document.createElement('a')
    link.href = url; link.download = `${detail.id}-mining-template.csv`; link.click(); URL.revokeObjectURL(url)
  }
  const visibleAIMapping = Object.fromEntries(Object.entries(aiMapping).filter(([, value]) => value.confidence >= aiThreshold))
  const semanticMatches = process ? process.steps.filter(step => Object.values(visibleAIMapping).some(value => value.step === step.id)) : []
  const semanticMissing = process ? process.steps.filter(step => !semanticMatches.some(match => match.id === step.id)) : []
  const semanticMapOnly = (detail?.nodes.filter(node => node.type === 'step') ?? []).filter(node => !Object.keys(visibleAIMapping).some(label => label === node.label))
  const runAIC = async () => {
    if (!detail || !process) return
    setAiBusy(true); setAiError(''); setAiMapping({})
    try {
      const response = await fetch('http://127.0.0.1:4183/api/map', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          activities: detail.nodes.filter(node => node.type === 'step').map(node => node.label),
          steps: process.steps.map(step => ({ id: step.id, label: step.name })),
        }),
      })
      if (!response.ok) throw new Error(`AI sidecar HTTP ${response.status}`)
      const data = await response.json() as { mapping: Record<string, string>; confidence?: Record<string, number> }
      const next: Record<string, { step: string; confidence: number }> = {}
      for (const [label, step] of Object.entries(data.mapping)) next[label] = { step, confidence: data.confidence?.[label] ?? 0 }
      setAiMapping(next)
    } catch (error) {
      setAiError(error instanceof Error ? error.message : 'AI unavailable')
    } finally { setAiBusy(false) }
  }
  const steps = (detail?.nodes.filter(node => node.type === 'step') ?? []).filter(step => {
    const value = search.toLowerCase()
    return !value || step.label.toLowerCase().includes(value) || (step.data?.role ?? '').toLowerCase().includes(value)
  })
  const downloadMap = () => {
    if (!detail) return
    const blob = new Blob([JSON.stringify({ schema: 'processlink-os-map-handoff/1', map: detail }, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob); const link = document.createElement('a')
    link.href = url; link.download = `${detail.id}-map-handoff.json`; link.click(); URL.revokeObjectURL(url)
  }

  return (
    <div className="osm-page">
      <PageHead title="OS maps" subtitle="Live DiagramForge documents through the same-origin OS session. Read-only; annotations stay local." />
      {maps === null ? <Empty title="Reading OS maps" detail="Waiting for the same-origin session." /> : maps.length === 0 ? <Empty title="No OS maps" detail="Create a map in DiagramForge first." /> : (
        <div className="split">
          <div className="list-pane">
            <div className="pane-head"><strong>{maps.length} maps</strong><Chip tone="green">Live</Chip></div>
            <div className="scroll-list">
              <input className="osmap-search" placeholder="Filter maps…" value={mapSearch} onChange={e => setMapSearch(e.target.value)} />
              {maps.filter(map => !mapSearch || map.label.toLowerCase().includes(mapSearch.toLowerCase())).map(map => (
                <button key={map.id} className="row" aria-selected={map.id === selected} onClick={() => setSelected(map.id)}>
                  <span style={{ minWidth: 0 }}>
                    <div className="title">{map.label}</div>
                    <div className="sub">{map.steps} steps · {map.state}{map.approved ? ' · approved' : ''}</div>
                  </span>
                </button>
              ))}
            </div>
          </div>
          <div className="detail-pane">
            {error && <p className="subtle" style={{ color: 'var(--orange)' }}>{error}</p>}
            {!detail ? <div className="subtle">Select a map.</div> : (
              <>
                <div className="rowflex" style={{ alignItems: 'baseline' }}>
                  <h2 style={{ margin: 0, fontSize: 18 }}>{detail.label}</h2>
                  <Chip tone="blue">{detail.schema}</Chip>
                  <div className="spacer" />
                  <button className="btn small" onClick={downloadMap}>Download map handoff</button>
                  <button className="btn small" onClick={downloadMiningCSV}>Mining CSV template</button>
                  <a className="btn small" href={`/console/apps/maps?map=${encodeURIComponent(detail.id)}`} target="_blank" rel="noreferrer">Open in DiagramForge</a>
                </div>
                <Card>
                  <KV items={[
                    ['Map id', detail.id],
                    ['Steps', String(steps.length)],
                    ['Edges', String(detail.edges?.length ?? 0)],
                    ['Source', 'Flightdeck OS · Maps'],
                  ]} />
                </Card>
                <Card title="Approval & releases" subtitle="DiagramForge lifecycle through the same OS session." glyph="✓">
                  <KV items={[
                    ['Approval', approval?.approved ?? 'Not approved'],
                    ['State', approval?.blocked ?? '—'],
                    ['Latest release', approval?.latestRelease ?? 'None'],
                    ['Draft matches release', approval?.draftMatchesRelease == null ? '—' : approval.draftMatchesRelease ? 'Yes' : 'No'],
                    ['Last editor', approval?.lastEditor ?? '—'],
                  ]} />
                  <div className="row-meta" style={{ marginTop: 6 }}>
                    <Chip tone={approval?.canApprove ? 'green' : 'orange'}>{approval?.canApprove ? 'Can approve' : 'Approval blocked'}</Chip>
                    <button className="btn small" onClick={() => {
                      if (!approval || !detail) return
                      const blob = new Blob([JSON.stringify({ schema: 'processlink-map-approval/1', map: detail.id, approval, releases }, null, 2)], { type: 'application/json' })
                      const url = URL.createObjectURL(blob); const link = document.createElement('a')
                      link.href = url; link.download = `${detail.id}-approval.json`; link.click(); URL.revokeObjectURL(url)
                    }}>Download approval record</button>
                  </div>
                  {releases.length === 0 ? <p className="subtle">No approved releases yet.</p> : releases.slice(0, 5).map((release, index) => (
                    <div className="row-meta" key={release.id ?? index} style={{ justifyContent: 'space-between', padding: '3px 0' }}>
                      <span>{release.version ?? release.id ?? `Release ${index + 1}`}</span><span className="tiny">{release.status ?? ''} {release.createdAt ? new Date(release.createdAt).toLocaleDateString('en-GB') : ''}</span>
                    </div>
                  ))}
                </Card>

                <Card title="Process comparison" subtitle="Compare live map steps with a ProcessLink process." glyph="⇄">
                  <div className="row-meta" style={{ marginBottom: 8 }}>
                    <select value={processId || process?.id || ''} onChange={e => setProcessId(e.target.value)} aria-label="Process">
                      {processes.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
                    </select>
                    <Chip tone="green">{Object.keys(aiMapping).length ? semanticMatches.length : matched.length} matched</Chip>
                    <Chip tone="orange">{Object.keys(aiMapping).length ? semanticMissing.length : missing.length} missing</Chip>
                    <Chip tone="blue">{Object.keys(aiMapping).length ? semanticMapOnly.length : extra.length} map-only</Chip>
                    <button className="btn small" onClick={runAIC} disabled={aiBusy || !detail || !process}>{aiBusy ? 'Thinking…' : 'AI compare'}</button>
                    <label className="tiny">min {Math.round(aiThreshold * 100)}%</label>
                    <input type="range" min={0.2} max={0.9} step={0.05} value={aiThreshold} onChange={e => setAiThreshold(Number(e.target.value))} aria-label="AI confidence threshold" />
                  </div>
                  {aiError && <div className="tiny" style={{ color: 'var(--orange)' }}>{aiError}</div>}
                  {Object.keys(aiMapping).length > 0 && (
                    <div className="tiny" style={{ marginBottom: 6 }}>
                      Semantic: {Object.entries(visibleAIMapping).slice(0, 3).map(([label, value]) => `${label} → ${process?.steps.find(step => step.id === value.step)?.name ?? value.step} (${Math.round(value.confidence * 100)}%)`).join(' · ')}
                    </div>
                  )}
                  {Object.keys(visibleAIMapping).length > 0 && (
                    <table className="table compact" style={{ marginBottom: 6 }}>
                      <thead><tr><th>Map activity</th><th>Process step</th><th className="num">Confidence</th></tr></thead>
                      <tbody>{Object.entries(visibleAIMapping).map(([label, value]) => (
                        <tr key={label}><td>{label}</td><td>{process?.steps.find(step => step.id === value.step)?.name ?? value.step}</td><td className="num">{Math.round(value.confidence * 100)}%</td></tr>
                      ))}</tbody>
                    </table>
                  )}
                  {missing.length > 0 && <div className="tiny">Missing: {missing.slice(0, 4).join(' · ')}</div>}
                  {extra.length > 0 && <div className="tiny">Map-only: {extra.slice(0, 4).join(' · ')}</div>}
                </Card>

                <Card title="Steps" subtitle="Live shape labels and roles; no write-back." glyph="▤">
                  <input className="osmap-search" placeholder="Search steps or roles…" value={search} onChange={e => setSearch(e.target.value)} />
                  {steps.map(step => (
                    <div className="osmap-step" key={step.id}>
                      <div className="rowflex">
                        <strong>{step.label}</strong>
                        <div className="spacer" />
                        {step.data?.statutory && <Chip tone="red">Statutory</Chip>}
                        {step.data?.humanOnly && <Chip tone="orange">Human only</Chip>}
                        <Chip>{step.data?.role ?? 'No role'}</Chip>
                        <FeedbackButton subject={{ kind: 'mapShape', subjectId: `os:${detail.id}#${step.id}`, subjectLabel: `${detail.label} · ${step.label}` }} />
                      </div>
                      {step.data?.description && <div className="tiny">{step.data.description}</div>}
                    </div>
                  ))}
                </Card>
                <Card title="Feedback on this map" subtitle="Local annotations; not written to DiagramForge." glyph="◌">
                  <FeedbackPanel subject={{ kind: 'map', subjectId: `os:${detail.id}`, subjectLabel: detail.label }} />
                </Card>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
