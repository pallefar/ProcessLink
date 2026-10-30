import { useState } from 'react'
import { useApp } from '../App'
import { Card, Chip, Empty, KV, Metric, Note, PageHead, stageTone } from '../components/ui'
import { fmt, initiativeLine, savingsConflicts, savingsTotal } from '../domain/rules'
import { METHOD_TITLE, STAGE_DETAIL, STAGE_LABEL, WASTE_LABEL } from '../domain/labels'
import type { Initiative, Step } from '../domain/types'
import { FeedbackButton } from '../components/FeedbackButton'

export default function Improvements() {
  const { initiatives, selectedInitiative, selectInitiative, commitSaving, advanceInitiative, validateSaving, processes } = useApp()
  const [validating, setValidating] = useState<string | null>(null)
  const lines = initiatives.map(initiativeLine)
  const totals = {
    estimated: savingsTotal(lines, 'estimated'),
    committed: savingsTotal(lines, 'committed'),
    validated: savingsTotal(lines, 'validated'),
  }
  const conflicts = savingsConflicts(lines)
  const selected = initiatives.find(i => i.id === selectedInitiative) ?? initiatives[0]

  return (
    <>
      <PageHead title="Improvements" subtitle="Every opportunity becomes a named owner, a method, a stage and a saving that a human validates." />

      <div className="grid metrics">
        <Metric glyph="✎" label="Estimated" value={fmt.hours(totals.estimated)} detail="Not a claim yet" />
        <Metric glyph="✍" label="Committed" value={fmt.hours(totals.committed)} detail="Owner and date agreed" />
        <Metric glyph="✓" label="Validated" value={fmt.hours(totals.validated)} detail={`${fmt.money(totals.validated)} at €52/h`} />
        <Metric glyph="▲" label="Double-count risk" value={String(conflicts.length)} detail={conflicts.length ? 'Resolve before roll-up' : 'One claim per process and waste'} />
      </div>

      <Card title="Savings ledger" subtitle="Hours are the source of truth. One claim per process and waste type is credited; ties never sum." glyph="▤">
        <table className="ledger">
          <thead><tr><th>Initiative</th><th>Waste</th><th>Stage</th><th className="num">Hours</th><th className="num">Per year</th></tr></thead>
          <tbody>
            {initiatives.map(initiative => (
              <tr key={initiative.id}>
                <td><button className="btn ghost small" style={{ padding: 0 }} onClick={() => selectInitiative(initiative.id)}>{initiative.title}</button></td>
                <td className="muted">{WASTE_LABEL[initiative.waste]}</td>
                <td><Chip tone={stageTone(initiative.savingsStage)}>{STAGE_LABEL[initiative.savingsStage]}</Chip></td>
                <td className="num">{fmt.hours(initiative.savingsHours)}</td>
                <td className="num">{fmt.money(initiative.savingsHours)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {conflicts.map(conflict => (
          <div key={conflict.key} style={{ marginTop: 10 }}>
            <Note glyph="▲">
              {processes.find(p => p.id === conflict.processId)?.name ?? conflict.processId} · {conflict.waste}: {conflict.initiativeIds.length} initiatives claim the same saving ({conflict.hours.map(h => fmt.hours(h)).join(' and ')}).
            </Note>
          </div>
        ))}
        {conflicts.length > 0 && <Note glyph="⛨">The ledger credits the most advanced claim per key. It never adds two initiatives that save the same hours.</Note>}
      </Card>

      <div className="split">
        <div className="list-pane">
          <div className="pane-head"><strong>{initiatives.length} initiatives</strong></div>
          <div className="scroll-list" role="listbox" aria-label="Initiatives">
            {initiatives.map(initiative => (
              <button key={initiative.id} className="row" aria-selected={initiative.id === selected?.id} onClick={() => selectInitiative(initiative.id)}>
                <span style={{ minWidth: 0 }}>
                  <div className="title">{initiative.title}</div>
                  <div className="sub">{METHOD_TITLE[initiative.method]} · {initiative.owner}</div>
                  <div className="rowflex" style={{ marginTop: 4 }}>
                    <Chip tone={stageTone(initiative.savingsStage)}>{STAGE_LABEL[initiative.savingsStage]}</Chip>
                    <Chip>{initiative.stage}</Chip>
                    <span className="tiny">due {new Date(initiative.due).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}</span>
                  </div>
                </span>
              </button>
            ))}
          </div>
        </div>
        <div className="detail-pane">
          {selected ? (
            <div className="stack">
              <div>
                <h2 style={{ margin: 0, fontSize: 17 }}>{selected.title}</h2>
                <FeedbackButton subject={{ kind: 'initiative', subjectId: selected.id, subjectLabel: selected.title }} />
                <div className="rowflex" style={{ marginTop: 6 }}>
                  <Chip tone={stageTone(selected.savingsStage)}>{STAGE_LABEL[selected.savingsStage]}</Chip>
                  <Chip>{METHOD_TITLE[selected.method]}</Chip>
                  <Chip>{selected.site}</Chip>
                </div>
              </div>

              <Card>
                <KV items={[
                  ['Owner', selected.owner],
                  ['Process', selected.processName],
                  ['Due', new Date(selected.due).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })],
                  ['Claim', `${fmt.hours(selected.savingsHours)} · ${STAGE_LABEL[selected.savingsStage]}`],
                  ...(selected.validatedBy ? [['Validated by', selected.validatedBy] as [string, string]] : []),
                ]} />
                {selected.evidence && <p className="tiny" style={{ marginTop: 8 }}>{selected.evidence}</p>}
                <div className="divider" />
                <div className="rowflex">
                  {(['plan', 'do', 'check', 'act'] as const).map(stage => (
                    <Chip key={stage} tone={selected.stage === stage ? 'blue' : undefined}>{stage}</Chip>
                  ))}
                  <div className="spacer" />
                  <button className="btn small" onClick={() => advanceInitiative(selected.id)} disabled={selected.stage === 'act'}>Move to {selected.stage === 'plan' ? 'Do' : selected.stage === 'do' ? 'Check' : 'Act'}</button>
                </div>
              </Card>

              <Card title="Savings lifecycle" subtitle="Each step needs a different human act." glyph="✓">
                <div className="grid three" style={{ gap: 12 }}>
                  {(['estimated', 'committed', 'validated'] as const).map(stage => (
                    <div key={stage} style={{ opacity: rank(selected.savingsStage) >= rank(stage) ? 1 : 0.55 }}>
                      <Chip tone={stageTone(stage)}>{STAGE_LABEL[stage]}</Chip>
                      <div className="tiny" style={{ marginTop: 4 }}>{STAGE_DETAIL[stage]}</div>
                    </div>
                  ))}
                </div>
                <div className="rowflex" style={{ marginTop: 12 }}>
                  <button className="btn small" onClick={() => commitSaving(selected.id)} disabled={selected.savingsStage !== 'estimated'}>Commit saving</button>
                  <button className="btn small" onClick={() => setValidating(selected.id)} disabled={selected.savingsStage === 'validated'}>Validate with evidence…</button>
                  <button className="btn small" onClick={() => downloadHandoff(selected, processes.find(p => p.id === selected.processId)?.steps ?? [])}>Download handoff (.md)</button>
                  <button className="btn small" onClick={() => downloadDeckBrief(selected, processes.find(p => p.id === selected.processId)?.steps ?? [])}>DeckForge brief</button>
                  <span className="tiny" style={{ marginLeft: 'auto' }}>{fmt.hours(selected.savingsHours)} · {fmt.money(selected.savingsHours)}</span>
                </div>
              </Card>

              <Card title="A3 · one page" subtitle="Background, target, countermeasure, result." glyph="▤">
                <KV items={[
                  ['Background', selected.background],
                  ['Target', selected.target],
                  ['Countermeasure', selected.countermeasure],
                  ['Result', selected.result || 'Not measured yet.'],
                ]} />
              </Card>

              {(selected.title.toLowerCase().includes('agent') || selected.title.toLowerCase().includes('bot')) && (
                <Card title="Automation / agent change package" subtitle="Required before anything is deployed." glyph="⚙">
                  <KV items={[
                    ['Scope', 'The exception path only; no change to the standard path.'],
                    ['Risks', 'Wrong automation of a statutory control; silent data loss; model drift.'],
                    ['Controls', 'Human review of every output; sample audit; kill switch.'],
                    ['Test plan', 'Shadow run for 2 weeks against the last 500 cases.'],
                    ['Approval', 'Required: process owner, CI manager, security. Not requested yet.'],
                  ]} />
                  <Note>ProcessLink never deploys or changes a production system. The package is a request for human approval.</Note>
                </Card>
              )}
            </div>
          ) : <Empty title="No initiative" detail="Promote an opportunity first." />}
        </div>
      </div>

      {validating && <ValidationDialog initiativeId={validating} onClose={() => setValidating(null)} onValidate={validateSaving} />}
    </>
  )
}

const rank = (stage: string) => stage === 'validated' ? 2 : stage === 'committed' ? 1 : 0

function downloadHandoff(initiative: Initiative, steps: Step[]) {
  const payload = {
    schema: 'processlink-automation-handoff/1',
    generatedAt: new Date().toISOString(),
    initiative: { id: initiative.id, title: initiative.title, owner: initiative.owner, process: initiative.processName, savingHours: initiative.savingsHours, savingStage: initiative.savingsStage },
    steps: steps.map(step => ({ id: step.id, name: step.name, role: step.role, application: step.application, minutes: step.minutes })),
    guardrails: ['No automatic send, release or performance decision.', 'A named human validates the KPI change and the saving.', 'This is a scaffold, not a deployment.'],
  }
  const text = `# Automation handoff — ${initiative.title}\n\nOwner: ${initiative.owner}\nProcess: ${initiative.processName}\n\n\`\`\`json\n${JSON.stringify(payload, null, 2)}\n\`\`\`\n\n## Test plan\n\n- Before/after KPI with a named validator\n- Human review of every output\n- Rollback owner and date\n`
  const blob = new Blob([text], { type: 'text/markdown' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url; link.download = `${initiative.id}-automation-handoff.md`
  link.click(); URL.revokeObjectURL(url)
}

function downloadDeckBrief(initiative: Initiative, steps: Step[]) {
  const text = `# ${initiative.title}\n\n**Owner:** ${initiative.owner}  \n**Process:** ${initiative.processName}  \n**Due:** ${new Date(initiative.due).toLocaleDateString('en-GB')}  \n**Saving:** ${initiative.savingsHours} h · ${initiative.savingsStage}  \n**Method:** ${initiative.method}\n\n## Background\n\n${initiative.background || '—'}\n\n## Target\n\n${initiative.target || '—'}\n\n## Countermeasure\n\n${initiative.countermeasure || '—'}\n\n## Process steps\n\n${steps.map((step, index) => `${index + 1}. ${step.name} — ${step.role} · ${step.application}`).join('\n')}\n\n## Guardrail\n\nA named human validates the KPI and saving. This brief is a handoff, not a claim.\n`
  const blob = new Blob([text], { type: 'text/markdown' }); const url = URL.createObjectURL(blob)
  const link = document.createElement('a'); link.href = url; link.download = `${initiative.id}-deckforge-brief.md`; link.click(); URL.revokeObjectURL(url)
}

function ValidationDialog({ initiativeId, onClose, onValidate }: {
  initiativeId: string
  onClose: () => void
  onValidate: (id: string, validator: string, evidence: string) => boolean
}) {
  const [validator, setValidator] = useState('')
  const [evidence, setEvidence] = useState('')
  return (
    <div className="backdrop" onClick={onClose}>
      <div className="dialog" role="dialog" aria-modal="true" aria-labelledby="validate-title" onClick={event => event.stopPropagation()}>
        <h2 id="validate-title">Validate the saving</h2>
        <p className="muted" style={{ margin: 0 }}>A saving becomes a claim only with a named validator and before/after evidence from in-house discovery.</p>
        <div className="field">
          <label htmlFor="validator">Validated by (name or role)</label>
          <input id="validator" value={validator} onChange={event => setValidator(event.target.value)} autoFocus />
        </div>
        <div className="field">
          <label htmlFor="evidence">Before/after evidence (period, metric, source)</label>
          <textarea id="evidence" value={evidence} onChange={event => setEvidence(event.target.value)} />
        </div>
        <div className="rowflex" style={{ justifyContent: 'flex-end' }}>
          <button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" disabled={!validator.trim() || evidence.trim().length < 12}
            onClick={() => { if (onValidate(initiativeId, validator, evidence)) onClose() }}>Validate</button>
        </div>
      </div>
    </div>
  )
}
