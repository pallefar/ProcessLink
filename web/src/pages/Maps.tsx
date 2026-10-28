import { useEffect, useMemo, useState } from 'react'
import { useApp } from '../App'
import { Card, Chip, Empty, KV, Note } from '../components/ui'
import { MapSvg, overlayText, type Overlay } from '../components/MapSvg'
import { fmt, scoreOpportunity } from '../domain/rules'
import { WASTE_LABEL } from '../domain/labels'
import type { Step } from '../domain/types'

const OVERLAYS: Array<{ id: Overlay; label: string }> = [
  { id: 'cycle', label: 'Cycle time' },
  { id: 'handoffs', label: 'Handoffs' },
  { id: 'rework', label: 'Rework' },
  { id: 'automation', label: 'Automation potential' },
]

interface Draft { label: string; role: string; system: string; minutes: string }

export default function Maps() {
  const {
    processes, selectedProcess, selectProcess, opportunities, initiatives, navigate, notify,
    selectNode, selectOpportunity,
  } = useApp()
  const eligible = processes.filter(p => p.status === 'discovered' && p.steps.length > 0)
  const process = eligible.find(p => p.id === selectedProcess) ?? eligible[0]

  const [overlay, setOverlay] = useState<Overlay>('cycle')
  const [selectedStepId, setSelectedStepId] = useState<string | undefined>(undefined)
  const [overrides, setOverrides] = useState<Record<string, Partial<Step>>>({})
  const [draft, setDraft] = useState<Draft>({ label: '', role: '', system: '', minutes: '' })

  useEffect(() => {
    const hottest = [...(process?.steps ?? [])].sort((a, b) => b.minutes - a.minutes)[0]
    setSelectedStepId(hottest?.id)
    setOverrides({})
  }, [process?.id])

  const steps = useMemo(() => (process?.steps ?? []).map(step => ({ ...step, ...overrides[step.id] })), [process, overrides])
  const mapped = useMemo(() => process ? { ...process, steps } : undefined, [process, steps])
  const step = steps.find(item => item.id === selectedStepId)
  const base = process?.steps.find(item => item.id === selectedStepId)

  useEffect(() => {
    if (!step) return
    setDraft({ label: step.name, role: step.role, system: step.application, minutes: String(step.minutes) })
    // Only reset when the selected shape changes; typing must not be clobbered.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step?.id])

  if (!process || !mapped) {
    return <Empty title="No map to draw" detail="A process with mined steps is needed." />
  }

  const topOpportunity = opportunities
    .filter(o => o.processId === process.id && o.status !== 'deferred')
    .sort((a, b) => scoreOpportunity(b).total - scoreOpportunity(a).total)[0]
  const validated = initiatives
    .filter(i => i.processId === process.id && i.savingsStage === 'validated')
    .reduce((sum, i) => sum + i.savingsHours, 0)

  const drift: Array<[string, string, string]> = []
  if (base && step) {
    if (step.name !== base.name) drift.push(['Label', step.name, base.name])
    if (step.role !== base.role) drift.push(['Role', step.role, base.role])
    if (step.application !== base.application) drift.push(['System', step.application, base.application])
    if (Math.abs(step.minutes - base.minutes) > 0.01) drift.push(['Time', fmt.minutes(step.minutes), fmt.minutes(base.minutes)])
  }

  const save = () => {
    if (!step) return
    const minutes = Number(draft.minutes)
    setOverrides(current => ({
      ...current,
      [step.id]: {
        name: draft.label,
        role: draft.role,
        application: draft.system,
        minutes: Number.isFinite(minutes) && minutes > 0 ? minutes : step.minutes,
      },
    }))
    notify('Map saved', 'Change recorded as a map proposal; discovery is not overwritten.', false)
  }

  const restore = () => {
    if (!step || !base) return
    setOverrides(current => {
      const next = { ...current }
      delete next[step.id]
      return next
    })
    setDraft({ label: base.name, role: base.role, system: base.application, minutes: String(base.minutes) })
    notify('Restored from discovery', base.name, false)
  }

  return (
    <div className="maps-workspace">
      <div className="map-toolbar">
        <select
          className="map-picker"
          aria-label="Flightdeck map"
          value={process.id}
          onChange={event => selectProcess(event.target.value)}
        >
          {eligible.map(item => <option key={item.id} value={item.id}>{item.name} — as-is</option>)}
        </select>
        <Chip>signavio-map/1</Chip>
        <span className="subtle inline-subtle">{process.site}</span>
        <div className="spacer" />
        <select
          className="map-overlay"
          aria-label="Overlay"
          value={overlay}
          onChange={event => setOverlay(event.target.value as Overlay)}
        >
          {OVERLAYS.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}
        </select>
        <button className="btn" onClick={() => { setOverrides({}); notify('Maps reloaded', 'Pulled the latest signavio-map/1 document.') }}>↻ Pull</button>
        <button className="icon-btn" aria-label="Map actions" title="Map actions" onClick={() => notify('Document', `${process.id} · ${process.steps.length} shapes · Flightdeck Maps owns this file.`)}>⋯</button>
      </div>

      <div className="map-surface">
        <MapSvg process={mapped} overlay={overlay} selected={step?.id} onSelect={next => setSelectedStepId(next.id)} />
        <div className="map-legend">
          <span>{process.steps.length} shapes · {process.steps.length} bound{steps[0] ? ` · ${overlayText(steps[0], overlay)}` : ''} …</span>
          <span>low <span className="heat-strip" aria-hidden="true" /> high</span>
        </div>
      </div>

      <div className="map-inspector">
        <Card title="Map fields" subtitle="Owned by Flightdeck Maps. Saving writes the document." glyph="▤">
          {step ? (
            <div className="map-fields">
              <label>Label<input value={draft.label} onChange={e => setDraft({ ...draft, label: e.target.value })} /></label>
              <label>Role / lane<input value={draft.role} onChange={e => setDraft({ ...draft, role: e.target.value })} /></label>
              <label>Application<input value={draft.system} onChange={e => setDraft({ ...draft, system: e.target.value })} /></label>
              <label className="inline-label">Minutes<input className="minutes" value={draft.minutes} onChange={e => setDraft({ ...draft, minutes: e.target.value })} /></label>
              <div className="rowflex">
                <button className="btn primary" onClick={save}>Save to map</button>
                <button className="btn" onClick={restore} disabled={!base}>Restore</button>
              </div>
            </div>
          ) : <Empty title="No shape selected" detail="Click a shape to edit it." />}
        </Card>

        <Card title="ProcessLink" subtitle="Live mined facts for this shape." glyph="⬡">
          {step ? (
            <>
              <KV items={[
                ['Process', process.name],
                ['Step', step.name],
                ['Time', fmt.minutes(step.minutes)],
                ['Handoffs', String(step.handoffs)],
                ['Rework', fmt.percent(step.rework)],
                ['Waste', WASTE_LABEL[step.waste]],
                ['KG node', <span className="mono">{step.kgId}</span>],
                ['Mined events', String(step.evidence)],
              ]} />
              {topOpportunity && (
                <div className="shape-opp">
                  <strong>{opportunities.filter(o => o.processId === process.id).length} opportunities on this process</strong>
                  <span>{topOpportunity.title}</span>
                  <div className="rowflex">
                    <Chip tone="orange">{fmt.hoursPerYear(topOpportunity.hours)}</Chip>
                    <button className="btn small" onClick={() => { selectOpportunity(topOpportunity.id); navigate('opportunities') }}>Open</button>
                  </div>
                </div>
              )}
              {validated > 0 && <div className="validated-line"><Chip tone="green">✓</Chip> {fmt.hours(validated)} validated on this process</div>}
            </>
          ) : <Empty title="No shape selected" detail="Mined metrics appear here." />}
        </Card>

        <Card title={drift.length ? 'Map differs from discovery' : 'Proposal rules'} subtitle="A proposal, not a silent overwrite." glyph={drift.length ? '⚠' : '⛨'}>
          {drift.length > 0 ? (
            <div className="drift-list">
              {drift.map(([label, mapValue, mined]) => (
                <div key={label}><span>{label}</span><strong>{mapValue}</strong><span className="subtle">mined {mined}</span></div>
              ))}
              <Note>Saving records a map change proposal. A human decides whether to update standard work or the map.</Note>
            </div>
          ) : (
            <Note>Select a shape or edit its fields. Saving records a map change proposal; the mined step is not overwritten.</Note>
          )}
          <div className="rowflex map-actions">
            <button className="btn small" onClick={() => { if (step) selectNode(step.kgId); navigate('graph') }} disabled={!step}>Open in KG</button>
            <button className="btn small" onClick={() => navigate('discoveries')}>Open process</button>
          </div>
        </Card>
      </div>
    </div>
  )
}
