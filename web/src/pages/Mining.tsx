import { useState } from 'react'
import { Card, Chip, Meter, Note } from '../components/ui'
import { fmt } from '../domain/rules'
import { useApp } from '../App'

const VARIANTS = [
  { path: 'Receive order → Check customer master → Validate pricing → Create sales order → Send confirmation', share: 0.33, cases: 8, cycle: 41, rework: 0 },
  { path: 'Receive order → Check customer master → Validate pricing → Release credit hold → Create sales order → Send confirmation', share: 0.33, cases: 8, cycle: 46, rework: 0 },
  { path: 'Receive order → Check customer master → Clear exception queue → Validate pricing → Create sales order → Send confirmation', share: 0.33, cases: 8, cycle: 60, rework: 0.14 },
]
const BOTTLENECKS = [
  { name: 'Send confirmation', wait: 12, rework: 0, fit: 0.36 },
  { name: 'Release credit hold', wait: 12, rework: 0, fit: 0.29 },
  { name: 'Clear exception queue', wait: 12, rework: 8, fit: 0.47 },
  { name: 'Validate pricing', wait: 10, rework: 0, fit: 0.28 },
  { name: 'Create sales order', wait: 10, rework: 0, fit: 0.36 },
  { name: 'Check customer master', wait: 6, rework: 0, fit: 0.36 },
  { name: 'Receive order', wait: 0, rework: 0, fit: 0.36 },
]
const SESSIONS = [
  { id: 'cap-1', name: 'Order desk · morning', role: 'Order Desk', site: 'Bensheim', date: 'Oct 27, 2026', minutes: 34, switches: 23, apps: 4 },
  { id: 'cap-2', name: 'Case triage · afternoon', role: 'Triage Agent', site: 'Manila', date: 'Oct 26, 2026', minutes: 41, switches: 31, apps: 4 },
]

export default function Mining() {
  const { notify } = useApp()
  const [mode, setMode] = useState<'logs' | 'capture'>('logs')
  const [selected, setSelected] = useState('ds-sample')
  const [reference, setReference] = useState<string>('Order intake & validation')
  const fitness = 0.72
  const exact = 8

  return (
    <>
      <div className="mining-toolbar">
        <div className="segmented" role="tablist" aria-label="Mining mode">
          <button role="tab" aria-selected={mode === 'logs'} onClick={() => setMode('logs')}>Process logs</button>
          <button role="tab" aria-selected={mode === 'capture'} onClick={() => setMode('capture')}>Task capture</button>
        </div>
        <div className="spacer" />
        {mode === 'logs' && (
          <>
            <button className="btn" onClick={() => notify('Sample log loaded', '24 cases · 144 events', false)}>Sample log</button>
            <button className="btn primary" onClick={() => notify('Import CSV', 'Desktop app supports the file picker; web import is next.', false)}>Import CSV</button>
          </>
        )}
      </div>

      {mode === 'logs' ? (
        <div className="split mining">
          <div className="list-pane">
            <div className="pane-head"><strong>1 dataset</strong><span className="spacer" /><button className="btn small ghost" onClick={() => notify('Import CSV', 'Desktop app supports the file picker; web import is next.')}>＋</button></div>
            <div className="scroll-list">
              {[
                { id: 'ds-sample', name: 'Order intake · mined sample', source: 'Sample', site: 'Bensheim', cases: 24, events: 144 },
              ].map(dataset => (
                <button key={dataset.id} className="list-row" aria-current={selected === dataset.id ? 'true' : undefined} onClick={() => setSelected(dataset.id)}>
                  <div className="row-title">{dataset.name}</div>
                  <div className="row-meta"><Chip>{dataset.source}</Chip><Chip>{dataset.site}</Chip></div>
                  <div className="row-sub">{dataset.cases} cases · {dataset.events} events</div>
                </button>
              ))}
            </div>
          </div>

          <div className="detail-pane mining-detail">
            <div className="detail-title-row">
              <div>
                <h2 className="detail-title">Order intake · mined sample</h2>
                <div className="row-meta" style={{ marginTop: 6 }}>
                  <Chip tone="blue">In-house sample</Chip>
                  <Chip>Internal</Chip>
                  <Chip>Bensheim</Chip>
                  <Chip>24 cases</Chip>
                  <Chip>144 events</Chip>
                  <Chip>Jan 1 – Jan 12, 2026</Chip>
                </div>
              </div>
              <button className="btn small ghost">Delete</button>
            </div>
            <p className="subtle">Synthetic 24-case log shipped with ProcessLink. No tenant data.</p>

            <div className="grid metrics five">
              <MetricBlock label="Median cycle" value="46 min" detail="P90 1.0 h" />
              <MetricBlock label="Variants" value="3" detail="Top path 33%" />
              <MetricBlock label="Rework" value="6%" detail="Repeated activities" />
              <MetricBlock label="Handoffs" value="30%" detail="Role changes between events" />
              <MetricBlock label="Automation candidates" value="0" detail="Score ≥ 0.55" />
            </div>

            <div className="grid two wide">
              <Card title="Variants" subtitle="The paths that actually ran, by case count." glyph="⇄">
                <div className="variant-list">
                  {VARIANTS.map((variant, index) => (
                    <div key={index} className="variant">
                      <div className="variant-head"><span>{variant.path}</span><strong>{fmt.percent(variant.share)}</strong></div>
                      <Meter label="" value={variant.share * 100} valueText="" tone={variant.rework > 0 ? 'orange' : 'teal'} />
                      <div className="variant-meta">{variant.cases} cases · {fmt.minutes(variant.cycle)} avg · {fmt.percent(variant.rework)} rework</div>
                    </div>
                  ))}
                </div>
              </Card>

              <Card title="Bottlenecks" subtitle="Wait, rework and handoffs by activity." glyph="▥">
                <table className="table compact">
                  <thead><tr><th>Activity</th><th className="num">Wait</th><th className="num">Rework</th><th className="num">Fit</th></tr></thead>
                  <tbody>
                    {BOTTLENECKS.map(row => (
                      <tr key={row.name}>
                        <td>{row.name}</td>
                        <td className="num">{fmt.minutes(row.wait)}</td>
                        <td className="num">{row.rework}</td>
                        <td className={`num ${row.fit >= 0.55 ? 'positive' : ''}`}>{fmt.percent(row.fit)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </Card>
            </div>

            <Card title="Conformance" subtitle="Compare the log with a documented standard path." glyph="✓">
              <div className="inline-row">
                <span className="subtle">Reference</span>
                <select value={reference} onChange={e => setReference(e.target.value)}>
                  <option>Order intake & validation</option>
                  <option>Customer case triage</option>
                </select>
                <span className="spacer" />
                <Chip tone="orange">{fmt.percent(fitness)} fit</Chip>
              </div>
              <Meter label="Sequence coverage" value={fitness * 100} valueText={fmt.percent(fitness)} tone="orange" />
              <p className="subtle">{exact} of 24 cases match the reference exactly; average sequence coverage is {fmt.percent(fitness)}. Missing: Clear exception queue · Release credit hold.</p>
              <Note>Fitness is sequence coverage, not a quality score. A deviation can be a local improvement; a human decides.</Note>
            </Card>

            <div className="inline-row">
              <button className="btn primary" onClick={() => notify('Discovered process created', '7 steps · 3 variants · in-house source')}>Create discovered process</button>
              <span className="subtle">The same records KYP.ai produces: process, steps, variants, KG bindings and one opportunity.</span>
            </div>
          </div>
        </div>
      ) : (
        <div className="capture-view">
          <Card title="Task capture" subtitle="Local only. The desktop app samples the frontmost app every two seconds." glyph="◉"
            actions={<Chip tone="green">Local only</Chip>}>
            <p className="subtle capture-copy">
              No window titles, keystrokes, clipboard, screenshots or names. Aggregates minutes and switches per app; nothing leaves the Mac.
            </p>
            <div className="capture-start">
              <input defaultValue="Desktop work" aria-label="Session name" />
              <input defaultValue="Order Desk" aria-label="Role" />
              <input defaultValue="Bensheim" aria-label="Site" />
              <button className="btn primary" onClick={() => notify('Capture is desktop-only', 'Open ProcessLink on macOS to start a live capture.')}>Start capture</button>
            </div>
            <p className="subtle">The button explains where capture runs; the browser cannot read other applications.</p>
          </Card>

          <Card title="Capture sessions" subtitle="Aggregates from the Mac; use one as a task-mining process." glyph="↺">
            <table className="table">
              <thead><tr><th>Session</th><th>Role</th><th className="num">Active</th><th className="num">Switches</th><th className="num">Apps</th><th /></tr></thead>
              <tbody>
                {SESSIONS.map(session => (
                  <tr key={session.id}>
                    <td><strong>{session.name}</strong><div className="row-sub">{session.date} · {session.site}</div></td>
                    <td>{session.role}</td>
                    <td className="num">{session.minutes} min</td>
                    <td className="num">{session.switches}</td>
                    <td className="num">{session.apps}</td>
                    <td className="num"><button className="btn small" onClick={() => notify('Task capture becomes a process', `${session.apps} app steps · estimate only`)}>Create process</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        </div>
      )}
    </>
  )
}

function MetricBlock({ label, value, detail }: { label: string; value: string; detail: string }) {
  return <div className="metric"><div className="label">{label}</div><div className="value">{value}</div><div className="detail">{detail}</div></div>
}
