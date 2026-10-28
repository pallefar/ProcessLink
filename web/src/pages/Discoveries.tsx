import { useApp, type Page } from '../App'
import { Card, Chip, Empty, KV, Metric, Note, PageHead } from '../components/ui'
import { evaluate, fmt } from '../domain/rules'
import { WASTE_LABEL } from '../domain/labels'
import type { PrivacyPolicy, Process } from '../domain/types'

export default function Discoveries() {
  const { processes, selectedProcess, selectProcess, policy, navigate } = useApp()
  const ordered = [...processes].sort((a, b) => {
    const rank = (status: string) => status === 'discovered' ? 0 : status === 'suppressed' ? 1 : 2
    return rank(a.status) - rank(b.status) || b.annualHours - a.annualHours
  })
  const process = ordered.find(p => p.id === selectedProcess) ?? ordered[0]

  return (
    <>
      <PageHead title="Discoveries" subtitle="What KYP.ai found, process by process: variants, steps, provenance, and the two reasons a record is shown as suppressed or blocked." />
      {!process ? <Empty title="No discoveries" detail="Connect the KYP.ai sandbox and run a sync." /> : (
        <div className="split">
          <div className="list-pane">
            <div className="pane-head"><strong>{ordered.length} processes</strong><span className="tiny" style={{ marginLeft: 'auto' }}>All sites</span></div>
            <div className="scroll-list" role="listbox" aria-label="Processes">
              {ordered.map(item => (
                <button key={item.id} className="row" role="option" aria-selected={item.id === process.id}
                  onClick={() => selectProcess(item.id)} style={{ alignItems: 'flex-start' }}>
                  <span aria-hidden="true" style={{ marginTop: 2, color: item.status === 'blocked' ? 'var(--red)' : item.status === 'suppressed' ? 'var(--orange)' : 'var(--green)' }}>●</span>
                  <span style={{ minWidth: 0 }}>
                    <div className="title">{item.name}</div>
                    <div className="sub">{item.site} · {item.valueStream}</div>
                    <div className="rowflex" style={{ marginTop: 4 }}>
                      <Chip tone={item.status === 'blocked' ? 'red' : item.status === 'suppressed' ? 'orange' : 'green'}>
                        {item.status === 'discovered' ? 'Discovered' : item.status === 'suppressed' ? 'Suppressed' : 'Blocked'}
                      </Chip>
                      {item.staleDays > 14 && item.status === 'discovered' && <Chip tone="orange">{item.staleDays}d old</Chip>}
                    </div>
                  </span>
                  {item.status === 'discovered' && <span className="right">{fmt.hoursPerYear(item.annualHours)}</span>}
                </button>
              ))}
            </div>
          </div>

          <div className="detail-pane">
            <div className="rowflex" style={{ alignItems: 'baseline' }}>
              <h2 style={{ margin: 0, fontSize: 18 }}>{process.name}</h2>
              <div className="spacer" />
              <Chip tone={process.status === 'blocked' ? 'red' : process.status === 'suppressed' ? 'orange' : 'green'}>
                {process.status === 'discovered' ? 'Discovered' : process.status === 'suppressed' ? 'Suppressed' : 'Blocked'}
              </Chip>
              <Chip tone={process.confidence >= 0.85 ? 'green' : 'orange'}>{fmt.percent(process.confidence)} confidence</Chip>
            </div>
            <div className="rowflex" style={{ marginTop: 8 }}>
              <Chip tone="blue">{process.site}</Chip>
              <Chip>KYP.ai task mining</Chip>
              <Chip>{process.businessUnit}</Chip>
              <Chip>{process.valueStream}</Chip>
              <Chip>Maturity {process.maturity}/5</Chip>
            </div>
            <p className="muted" style={{ marginTop: 10 }}>{process.summary}</p>

            {process.status !== 'discovered'
              ? <Guarded process={process} />
              : <Discovered process={process} policy={policy} navigate={navigate} />}
          </div>
        </div>
      )}
    </>
  )
}

function Guarded({ process }: { process: Process }) {
  return (
    <Card title={process.status === 'blocked' ? 'Blocked by classification' : 'Suppressed by group size'}
      subtitle={process.statusReason} glyph="⛨">
      <p className="muted">
        {process.status === 'blocked'
          ? 'Restricted content never enters ProcessLink. The process appears only so an operator can see that data exists and is being refused — there are no numbers, steps or variants to open.'
          : `This group of ${process.people} people is below the threshold. ProcessLink shows that the process exists and the reason it is hidden; it never computes or displays an aggregate for a group this small.`}
      </p>
      <div className="rowflex" style={{ marginTop: 10 }}>
        {process.status === 'blocked'
          ? <><Chip tone="red">Restricted</Chip><Chip tone="red">No AI call</Chip><Chip tone="red">No export</Chip></>
          : <><Chip tone="orange">Suppressed</Chip><Chip tone="orange">No aggregate shown</Chip></>}
      </div>
      <KV items={[
        ['Group size', `${process.people} people`],
        ['KYP.ai id', <span className="mono">{process.kypId}</span>],
        ['Classification', process.classification],
      ]} />
      <Note>The threshold is set by policy and reviewed with employee representatives; it is not a per-user preference.</Note>
    </Card>
  )
}

function Discovered({ process, policy, navigate }: {
  process: Process
  policy: PrivacyPolicy
  navigate: (page: Page) => void
}) {
  const decision = evaluate({ groupSize: process.people, classification: process.classification, destination: 'knowledgeGraph', purpose: 'processImprovement', policy })
  return (
    <div className="stack" style={{ marginTop: 14 }}>
      <div className="grid metrics" style={{ gridTemplateColumns: 'repeat(4, minmax(0, 1fr))' }}>
        <Metric label="Annual effort" value={fmt.hoursPerYear(process.annualHours)} detail={`${process.people} people, aggregate only`} />
        <Metric label="Median cycle" value={fmt.minutes(process.cycleMinutes)} detail={`${process.handoffs} handoffs`} />
        <Metric label="Rework" value={fmt.percent(process.reworkRate)} detail="Touches that repeat a step" />
        <Metric label="Adherence" value={fmt.percent(process.adherence)} detail={process.standardVersion} />
      </div>

      <Card title="Variants" subtitle={`The same process, mined as ${process.variants.length} paths.`} glyph="⇄">
        <div className="stack" style={{ gap: 10 }}>
          {process.variants.map(variant => (
            <div key={variant.name}>
              <div className="between">
                <span style={{ fontSize: 12 }}>{variant.name}</span>
                <span className="tiny">{fmt.percent(variant.share)} of cases</span>
              </div>
              <div className="track" style={{ height: 5, background: 'color-mix(in srgb, var(--text) 12%, transparent)', borderRadius: 999, overflow: 'hidden', margin: '4px 0' }}>
                <div style={{ height: '100%', width: `${variant.share * 100}%`, background: variant.rework > process.reworkRate ? 'var(--orange)' : 'var(--accent)' }} />
              </div>
              <div className="tiny">{fmt.minutes(variant.cycle)} · {fmt.percent(variant.rework)} rework · {variant.path}</div>
            </div>
          ))}
        </div>
      </Card>

      <Card title="Steps" subtitle="Role and application as KYP.ai classified them. No person is shown." glyph="≡">
        <table className="ledger">
          <thead><tr><th>Step</th><th>Role</th><th>Application</th><th className="num">Time</th><th>Waste</th></tr></thead>
          <tbody>
            {process.steps.map(step => (
              <tr key={step.id}>
                <td>{step.name}{step.handoffs > 0 && <span className="tiny"> →</span>}</td>
                <td className="muted">{step.role}</td>
                <td className="muted">{step.application}</td>
                <td className="num">{fmt.minutes(step.minutes)}</td>
                <td><Chip tone={step.waste === 'rework' ? 'orange' : step.waste === 'handoffs' ? 'teal' : undefined}>{WASTE_LABEL[step.waste]}</Chip></td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>

      <div className="grid two">
        <Card title="Provenance" subtitle="Every fact carries its source and window." glyph="⌁">
          <KV items={[
            ['Source', 'KYP.ai task mining'],
            ['KYP.ai id', <span className="mono">{process.kypId}</span>],
            ['KG node', <span className="mono">{process.kgId}</span>],
            ['Last sync', `${process.staleDays} days ago`],
            ['Group size', `${process.people} people · aggregate only`],
            ['Classification', process.classification],
          ]} />
        </Card>
        <Card title="Standard work" subtitle="The documented path the mining is compared with." glyph="▤">
          <KV items={[
            ['Document', process.standard],
            ['Version', process.standardVersion],
            ['Adherence', fmt.percent(process.adherence)],
            ['Deviating steps', String(process.steps.filter(s => !s.standardAligned).length)],
          ]} />
          <Note>A standard-work change is proposed, never applied. A human owner approves the new standard.</Note>
        </Card>
      </div>

      <div className="rowflex">
        <button className="btn primary" onClick={() => navigate('opportunities')}>Open opportunities</button>
        <button className="btn" onClick={() => navigate('maps')}>Open map</button>
        <span className="tiny" style={{ marginLeft: 'auto' }}>{decision.allowed ? 'Eligible for KG write' : decision.reason}</span>
      </div>
    </div>
  )
}
