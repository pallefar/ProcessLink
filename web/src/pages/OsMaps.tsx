import { useEffect, useState } from 'react'
import { Card, Chip, Empty, KV, PageHead } from '../components/ui'
import { FeedbackPanel } from '../components/FeedbackPanel'
import { osGet, type LiveMap } from '../domain/osBridge'

interface MapNode { id: string; type: string; label: string; data?: { role?: string; description?: string; stepId?: string; statutory?: boolean; humanOnly?: boolean } }
interface MapDetail { schema: string; id: string; label: string; nodes: MapNode[]; edges: Array<{ id: string; source: string; target: string }> }

export default function OsMaps() {
  const [maps, setMaps] = useState<LiveMap[] | null>(null)
  const [selected, setSelected] = useState('')
  const [detail, setDetail] = useState<MapDetail | null>(null)
  const [error, setError] = useState('')

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

  const steps = detail?.nodes.filter(node => node.type === 'step') ?? []

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
                <Card title="Steps" subtitle="Live shape labels and roles; no write-back." glyph="▤">
                  {steps.map(step => (
                    <div className="osmap-step" key={step.id}>
                      <div className="rowflex">
                        <strong>{step.label}</strong>
                        <div className="spacer" />
                        {step.data?.statutory && <Chip tone="red">Statutory</Chip>}
                        {step.data?.humanOnly && <Chip tone="orange">Human only</Chip>}
                        <Chip>{step.data?.role ?? 'No role'}</Chip>
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
