import { useEffect, useState } from 'react'
import { Card, Chip, Empty, KV, PageHead } from '../components/ui'
import { useApp } from '../App'
import { FeedbackPanel } from '../components/FeedbackPanel'
import { FeedbackButton } from '../components/FeedbackButton'
import { osGet, type LiveMap } from '../domain/osBridge'

interface MapNode { id: string; type: string; label: string; data?: { role?: string; description?: string; stepId?: string; statutory?: boolean; humanOnly?: boolean } }
interface MapDetail { schema: string; id: string; label: string; nodes: MapNode[]; edges: Array<{ id: string; source: string; target: string }> }

export default function OsMaps() {
  const { processes } = useApp()
  const [processId, setProcessId] = useState('')
  const [maps, setMaps] = useState<LiveMap[] | null>(null)
  const [selected, setSelected] = useState('')
  const [detail, setDetail] = useState<MapDetail | null>(null)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')

  useEffect(() => {
    void osGet<LiveMap[]>('/api/apps/maps/maps').then(value => {
      setMaps(value)
      if (value?.[0]) setSelected(value[0].id)
    })
  }, [])

  useEffect(() => {
    if (!selected) return
    setDetail(null); setError('')
    void osGet<MapDetail>(`/api/apps/maps/maps/${encodeURIComponent(selected)}`).then(value => {
      if (value) setDetail(value); else setError('The OS map could not be read with this session.')
    })
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
              {maps.map(map => (
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
                <Card title="Process comparison" subtitle="Compare live map steps with a ProcessLink process." glyph="⇄">
                  <div className="row-meta" style={{ marginBottom: 8 }}>
                    <select value={processId || process?.id || ''} onChange={e => setProcessId(e.target.value)} aria-label="Process">
                      {processes.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
                    </select>
                    <Chip tone="green">{matched.length} matched</Chip>
                    <Chip tone="orange">{missing.length} missing</Chip>
                    <Chip tone="blue">{extra.length} map-only</Chip>
                  </div>
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
