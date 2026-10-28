import { useEffect, useState } from 'react'
import { useApp } from '../App'
import { Card, Chip, Empty, KV, Note, PageHead, routeTone } from '../components/ui'
import { MapSvg, type Overlay } from '../components/MapSvg'
import { fmt, scoreOpportunity } from '../domain/rules'
import { WASTE_LABEL } from '../domain/labels'

const OVERLAYS: Array<{ id: Overlay; label: string }> = [
  { id: 'cycle', label: 'Cycle time' },
  { id: 'handoffs', label: 'Handoffs' },
  { id: 'rework', label: 'Rework' },
  { id: 'automation', label: 'Automation potential' },
]

export default function Maps() {
  const { processes, selectedProcess, selectProcess, opportunities, selectOpportunity, navigate, notify, selectNode } = useApp()
  const eligible = processes.filter(p => p.status === 'discovered' && p.steps.length > 0)
  const process = eligible.find(p => p.id === selectedProcess) ?? eligible[0]
  const [overlay, setOverlay] = useState<Overlay>('cycle')
  const [selectedStep, setSelectedStep] = useState<string | undefined>(undefined)

  useEffect(() => {
    const hottest = [...(process?.steps ?? [])].sort((a, b) => b.minutes - a.minutes)[0]
    setSelectedStep(hottest?.id)
  }, [process?.id])

  if (!process) {
    return <><PageHead title="Maps" subtitle="Generated from KYP.ai." /><Empty title="No map to draw" detail="A process with mined steps is needed." /></>
  }

  const step = process.steps.find(s => s.id === selectedStep)
  const best = opportunities
    .filter(o => o.processId === process.id && o.status !== 'deferred')
    .sort((a, b) => scoreOpportunity(b).total - scoreOpportunity(a).total)[0]

  return (
    <>
      <PageHead
        title="Process map"
        subtitle="Generated from KYP.ai, bound shape by shape to the knowledge graph. Edits here propose a KG change; they never overwrite discovery."
        actions={
          <>
            <select
              aria-label="Process to map"
              value={process.id}
              onChange={event => selectProcess(event.target.value)}
              style={{ border: '1px solid var(--border-strong)', background: 'var(--panel)', borderRadius: 8, padding: '4px 8px', fontSize: 12 }}
            >
              {eligible.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
            </select>
            <button className="btn" onClick={() => notify('Map regenerated', `${process.steps.length} shapes re-bound to live KG nodes.`)}>↻ Regenerate</button>
          </>
        }
      />

      {process.staleDays > 14 && (
        <div className="card" style={{ borderColor: 'color-mix(in srgb, var(--orange) 40%, transparent)', background: 'var(--orange-weak)' }}>
          <div className="rowflex">
            <span aria-hidden="true">▲</span>
            <span>This map was last generated from evidence {process.staleDays} days old. It no longer matches the latest discovery.</span>
            <button className="btn small" style={{ marginLeft: 'auto' }} onClick={() => notify('Sync started', 'A new batch will refresh the map.')}>Sync now</button>
          </div>
        </div>
      )}

      <Card
        title={`As-is · ${process.name}`}
        subtitle={`${process.steps.length} steps · ${process.handoffs} handoffs · ${fmt.minutes(process.cycleMinutes)} median cycle · every shape is a KG node`}
        glyph="⌁"
        actions={
          <div className="rowflex" role="tablist" aria-label="Map overlay">
            {OVERLAYS.map(item => (
              <button key={item.id} className={item.id === overlay ? 'btn small primary' : 'btn small'} role="tab" aria-selected={item.id === overlay} onClick={() => setOverlay(item.id)}>
                {item.label}
              </button>
            ))}
          </div>
        }
      >
        <MapSvg process={process} overlay={overlay} selected={step?.id} onSelect={next => setSelectedStep(next.id)} />
        <div className="between" style={{ marginTop: 8 }}>
          <span className="tiny">Drawn from {process.kypId}. Hue and the number on each shape carry the same overlay value.</span>
          <span className="tiny">low <span aria-hidden="true" style={{ display: 'inline-block', width: 56, height: 6, borderRadius: 999, background: 'linear-gradient(to right, var(--green), var(--orange), var(--red))', verticalAlign: 'middle' }} /> high</span>
        </div>
      </Card>

      <div className="grid two">
        <Card title="Shape detail" subtitle="Bound to the knowledge graph." glyph="⌖">
          {step ? (
            <>
              <div className="rowflex" style={{ marginBottom: 8 }}>
                <strong style={{ fontSize: 13 }}>{step.name}</strong>
                <Chip tone="orange">{WASTE_LABEL[step.waste]}</Chip>
              </div>
              <KV items={[
                ['Role', step.role],
                ['Application', step.application],
                ['Time', fmt.minutes(step.minutes)],
                ['Handoffs', String(step.handoffs)],
                ['Rework share', fmt.percent(step.rework)],
                ['Evidence', `${step.evidence} mined events`],
                ['Standard', step.standardAligned ? 'Aligned with the SOP' : 'Deviates from the SOP'],
                ['KG node', <span className="mono">{step.kgId}</span>],
              ]} />
              <div className="rowflex" style={{ marginTop: 10 }}>
                <button className="btn small" onClick={() => { selectNode(step.kgId); navigate('graph') }}>Open in KG</button>
                <button className="btn small" onClick={() => notify('SOP linked', 'Knowledge Guardian will open the linked document.')}>Open SOP</button>
              </div>
              <Note>This shape shows an aggregate. There is no per-person drill-down, by design.</Note>
            </>
          ) : <Empty title="No shape selected" detail="Click a shape to see its binding." />}
        </Card>

        <Card title="Variant comparison" subtitle="Where the paths diverge." glyph="⇄">
          <div className="stack" style={{ gap: 10 }}>
            {process.variants.map(variant => (
              <div key={variant.name}>
                <div className="between">
                  <span style={{ fontSize: 12 }}>{variant.name}</span>
                  <span className="tiny">{fmt.minutes(variant.cycle)} · {fmt.percent(variant.rework)} rework</span>
                </div>
                <div style={{ height: 5, borderRadius: 999, background: 'var(--border)', overflow: 'hidden', margin: '4px 0' }}>
                  <div style={{ height: '100%', width: `${variant.share * 100}%`, background: variant.rework > 0.3 ? 'var(--orange)' : 'var(--accent)' }} />
                </div>
                <div className="tiny" style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{variant.path}</div>
              </div>
            ))}
          </div>
        </Card>
      </div>

      <Card title="As-is vs to-be" subtitle="A to-be map is an opportunity, not a promise." glyph="⇥">
        {best ? (
          <div className="rowflex" style={{ alignItems: 'flex-end', gap: 24 }}>
            <div>
              <div className="tiny">As-is</div>
              <div style={{ fontSize: 24, fontWeight: 650 }}>{fmt.hoursPerYear(process.annualHours)}</div>
              <div className="tiny">{process.steps.length} steps · {fmt.percent(process.reworkRate)} rework</div>
            </div>
            <div aria-hidden="true" className="muted">→</div>
            <div>
              <div className="tiny">To-be</div>
              <div style={{ fontSize: 24, fontWeight: 650 }}>{fmt.hoursPerYear(Math.max(0, process.annualHours - best.hours))}</div>
              <div className="tiny">{best.route}: {best.title}</div>
            </div>
            <div style={{ marginLeft: 'auto', textAlign: 'right' }} className="stack">
              <Chip tone={routeTone(best.route)}>Projected −{fmt.hours(best.hours)}</Chip>
              <span className="tiny">Estimate · {fmt.percent(best.confidence)} confidence</span>
              <button className="btn small" onClick={() => { selectOpportunity(best.id); navigate('opportunities') }}>Open opportunity</button>
            </div>
          </div>
        ) : <Empty title="No opportunity linked" detail="Promote a discovered process first." />}
      </Card>
    </>
  )
}
