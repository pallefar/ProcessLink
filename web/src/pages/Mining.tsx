import { useMemo, useRef, useState } from 'react'
import { Card, Chip, Metric, Note } from '../components/ui'
import { MiningGraph } from '../components/MiningGraph'
import { useApp } from '../App'
import { fmt } from '../domain/rules'
import {
  buildCases, conformance, filterEvents, mine, parseEventCSV, rootCauses, sampleCSV, simulate,
  type MiningEvent, type MiningFilter,
} from '../domain/mining'

type Tab = 'overview' | 'process' | 'cases' | 'conformance' | 'insights' | 'simulate'

export default function Mining() {
  const { notify } = useApp()
  const [mode, setMode] = useState<'logs' | 'capture'>('logs')
  const [tab, setTab] = useState<Tab>('overview')
  const [datasetName, setDatasetName] = useState('Order intake · mined sample')
  const [events, setEvents] = useState<MiningEvent[]>(() => parseEventCSV(sampleCSV()))
  const [filter, setFilter] = useState<MiningFilter>({})
  const [selectedActivity, setSelectedActivity] = useState<string>()
  const [selectedCase, setSelectedCase] = useState<string>()
  const [caseSearch, setCaseSearch] = useState('')
  const [automate, setAutomate] = useState<Set<string>>(new Set())
  const [remove, setRemove] = useState<Set<string>>(new Set())
  const [reworkReduction, setReworkReduction] = useState(0)
  const [waitReduction, setWaitReduction] = useState(0)
  const fileInput = useRef<HTMLInputElement>(null)

  const baseline = useMemo(() => mine(events), [events])
  const filtered = useMemo(() => filterEvents(events, filter), [events, filter])
  const mined = useMemo(() => mine(filtered), [filtered])
  const reference = mined.variants[0]?.path.split(' → ') ?? []
  const conformanceResult = useMemo(() => conformance(filtered, reference), [filtered, reference.join('|')])
  const causes = useMemo(() => rootCauses(mined.caseRecords, 'slow'), [mined])
  const simulation = useMemo(() => simulate(mined.caseRecords, automate, remove, reworkReduction, waitReduction), [mined, automate, remove, reworkReduction, waitReduction])
  const currentCase = mined.caseRecords.find(c => c.id === selectedCase)
  const activities = baseline.activities.map(a => a.name).sort()
  const resources = [...new Set(events.map(e => e.resource))].sort()
  const attributeKeys = [...new Set(events.flatMap(e => Object.keys(e.attributes)))]

  const importFile = async (file: File) => {
    const text = await file.text()
    const parsed = parseEventCSV(text)
    if (!parsed.length) { notify('Import failed', 'No case_id/activity/timestamp rows found.', true); return }
    setEvents(parsed)
    setDatasetName(file.name.replace(/\.csv$/i, ''))
    setSelectedCase(undefined)
    notify('Event log imported', `${buildCases(parsed).length} cases · ${parsed.length} events`)
  }

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
            <button className="btn" onClick={() => { setEvents(parseEventCSV(sampleCSV())); setDatasetName('Order intake · mined sample'); setFilter({}) }}>Sample log</button>
            <button className="btn primary" onClick={() => fileInput.current?.click()}>Import CSV</button>
            <input ref={fileInput} type="file" accept=".csv,text/csv" hidden
              onChange={event => { const file = event.target.files?.[0]; if (file) void importFile(file) }} />
          </>
        )}
      </div>

      {mode === 'logs' ? (
        <div className="mining-workbench">
          <div className="mining-head">
            <div>
              <h2 className="detail-title">{datasetName}</h2>
              <div className="row-meta">
                <Chip>ProcessLink discovery</Chip>
                <Chip>{mined.cases} of {baseline.cases} cases</Chip>
                <Chip>{mined.events} events</Chip>
                {filter.activity || filter.resource || filter.reworkOnly ? <Chip tone="orange">Filtered</Chip> : null}
              </div>
            </div>
            <div className="row-meta mining-metrics-inline">
              <Chip>{mined.activities.length} activities</Chip>
              <Chip>{mined.variants.length} variants</Chip>
              <Chip>{fmt.percent(mined.reworkRate)} rework</Chip>
            </div>
          </div>

          <div className="mining-filters">
            <select value={filter.activity ?? ''} onChange={e => setFilter(f => ({ ...f, activity: e.target.value || undefined }))} aria-label="Activity filter">
              <option value="">All activities</option>
              {activities.map(a => <option key={a} value={a}>{a}</option>)}
            </select>
            <select value={filter.resource ?? ''} onChange={e => setFilter(f => ({ ...f, resource: e.target.value || undefined }))} aria-label="Role filter">
              <option value="">All roles</option>
              {resources.map(r => <option key={r} value={r}>{r}</option>)}
            </select>
            <select value={filter.attributeKey ?? ''} onChange={e => setFilter(f => ({ ...f, attributeKey: e.target.value || undefined, attributeValue: undefined }))} aria-label="Attribute dimension">
              <option value="">All dimensions</option>
              {attributeKeys.map(k => <option key={k} value={k}>{k}</option>)}
            </select>
            {filter.attributeKey && (
              <select value={filter.attributeValue ?? ''} onChange={e => setFilter(f => ({ ...f, attributeValue: e.target.value || undefined }))} aria-label="Attribute value">
                <option value="">Any value</option>
                {[...new Set(events.map(e => e.attributes[filter.attributeKey!]).filter(Boolean))].sort().map(v => <option key={v} value={v}>{v}</option>)}
              </select>
            )}
            <label className="tiny"><input type="checkbox" checked={!!filter.reworkOnly} onChange={e => setFilter(f => ({ ...f, reworkOnly: e.target.checked }))} /> Rework only</label>
            <div className="spacer" />
            <button className="btn small" onClick={() => setFilter({})} disabled={!filter.activity && !filter.resource && !filter.reworkOnly && !filter.attributeKey}>Reset</button>
          </div>

          <div className="segmented mining-tabs" role="tablist">
            {(['overview', 'process', 'cases', 'conformance', 'insights', 'simulate'] as Tab[]).map(item => (
              <button key={item} role="tab" aria-selected={tab === item} onClick={() => setTab(item)}>{item.charAt(0).toUpperCase() + item.slice(1)}</button>
            ))}
          </div>

          {tab === 'overview' && (
            <div className="mining-tab">
              <div className="grid metrics five">
                <Metric label="Cases" value={String(mined.cases)} detail="In the current view" />
                <Metric label="Median cycle" value={fmt.minutes(mined.median)} detail={`P90 ${fmt.minutes(mined.p90)}`} />
                <Metric label="Rework" value={fmt.percent(mined.reworkRate)} detail={`${mined.caseRecords.filter(c => c.rework > 0).length} cases`} />
                <Metric label="Handoffs" value={fmt.percent(mined.handoffRate)} detail="Role changes" />
                <Metric label="Cost / case" value={fmt.euro(mined.cases ? mined.cost / mined.cases : 0)} detail={fmt.euro(mined.cost) + ' observed'} />
              </div>

              <div className="grid two wide">
                <Card title="Variants" subtitle="Every distinct path, ranked by case count." glyph="⇄">
                  <div className="variant-list">
                    {mined.variants.slice(0, 7).map(variant => (
                      <div key={variant.path} className="variant">
                        <div className="variant-head"><span>{variant.path}</span><strong>{fmt.percent(variant.share)}</strong></div>
                        <div className="track"><div className="fill" style={{ width: `${variant.share * 100}%` }} /></div>
                        <div className="variant-meta">{variant.cases} cases · {fmt.minutes(variant.cycle)} avg · {fmt.percent(variant.rework)} rework</div>
                      </div>
                    ))}
                  </div>
                </Card>
                <Card title="Bottlenecks" subtitle="Wait and automation fit by activity." glyph="▥">
                  <table className="table compact">
                    <thead><tr><th>Activity</th><th className="num">Wait</th><th className="num">Rework</th><th className="num">Fit</th></tr></thead>
                    <tbody>
                      {[...mined.activities].sort((a, b) => b.wait - a.wait).slice(0, 7).map(activity => (
                        <tr key={activity.name}><td>{activity.name}</td><td className="num">{fmt.minutes(activity.wait)}</td><td className="num">{activity.rework}</td><td className="num">{fmt.percent(activity.automation)}</td></tr>
                      ))}
                    </tbody>
                  </table>
                </Card>
              </div>

              <Card title="Watchlist" subtitle="Explainable signals, not automatic decisions." glyph="◷">
                {mined.alerts.length === 0 ? <p className="subtle">No threshold crossed in this view.</p> : (
                  <div className="stack" style={{ gap: 6 }}>
                    {mined.alerts.map(alert => (
                      <div key={alert.id} className="rowflex" style={{ gap: 8 }}>
                        <Chip tone={alert.severity === 'critical' ? 'red' : alert.severity === 'warning' ? 'orange' : 'blue'}>{alert.severity}</Chip>
                        <strong style={{ fontSize: 12 }}>{alert.title}</strong>
                        <span className="subtle">{alert.detail}</span>
                      </div>
                    ))}
                  </div>
                )}
              </Card>
            </div>
          )}

          {tab === 'process' && (
            <div className="mining-tab">
              <Card title="Discovered process" subtitle="Directly-follows graph; edge width is frequency." glyph="⌁">
                <MiningGraph mined={mined} selected={selectedActivity} onSelect={setSelectedActivity} />
                <p className="subtle">Click a shape to inspect it. Activities are ordered by the dominant variant.</p>
              </Card>
              {selectedActivity && (() => {
                const info = mined.activities.find(a => a.name === selectedActivity)
                if (!info) return null
                return <Card title={info.name} subtitle={`${info.events} events across ${info.cases} cases`} glyph="▤">
                  <table className="table"><tbody>
                    <tr><td>Average wait</td><td>{fmt.minutes(info.wait)}</td></tr>
                    <tr><td>Rework events</td><td>{info.rework}</td></tr>
                    <tr><td>Handoffs</td><td>{info.handoffs}</td></tr>
                    <tr><td>Roles</td><td>{info.resources.join(', ')}</td></tr>
                    <tr><td>Automation fit</td><td>{fmt.percent(info.automation)}</td></tr>
                  </tbody></table>
                </Card>
              })()}
            </div>
          )}

          {tab === 'cases' && (
            <div className="mining-cases">
              <Card title="Cases" subtitle={`${mined.cases} cases in view`} glyph="☷">
                <input className="mining-search" value={caseSearch} onChange={e => setCaseSearch(e.target.value)} placeholder="Search case or variant" aria-label="Search cases" />
                <div className="case-list">
                  {mined.caseRecords.filter(c => !caseSearch || c.id.includes(caseSearch) || c.variant.includes(caseSearch)).map(record => (
                    <button key={record.id} className="case-row" data-selected={selectedCase === record.id}
                      onClick={() => setSelectedCase(record.id)}>
                      <span className="mono">{record.id.slice(0, 14)}</span>
                      <span>{fmt.minutes(record.cycle)}</span>
                      <span className="row-sub">{record.variant}</span>
                    </button>
                  ))}
                </div>
              </Card>
              <Card title={currentCase ? `Case ${currentCase.id}` : 'Select a case'} subtitle={currentCase ? `${fmt.minutes(currentCase.cycle)} · ${currentCase.events.length} events` : 'Pick a case from the list'} glyph="◷">
                {currentCase && (
                  <div className="case-timeline">
                    <div className="row-meta">
                      <Chip tone={currentCase.rework ? 'orange' : 'green'}>{currentCase.rework} rework</Chip>
                      <Chip tone="purple">{currentCase.handoffs} handoffs</Chip>
                      {currentCase.cost > 0 && <Chip tone="green">{fmt.euro(currentCase.cost)}</Chip>}
                    </div>
                    <p className="subtle">{currentCase.variant}</p>
                    {currentCase.events.map((event, index) => {
                      const previous = index ? currentCase.events[index - 1] : undefined
                      const delta = previous ? (event.timestamp - previous.timestamp) / 60_000 : 0
                      return <div key={index} className="case-event">
                        <span className="case-dot" />
                        <div><strong>{event.activity}</strong>
                          <div className="row-sub">{event.resource} · {event.application}{delta > 0 ? ` · +${fmt.minutes(delta)}` : ''}</div>
                          <div className="row-sub">{new Date(event.timestamp).toLocaleString('en-GB')}</div>
                        </div>
                      </div>
                    })}
                  </div>
                )}
              </Card>
            </div>
          )}

          {tab === 'conformance' && (
            <div className="mining-tab">
              <Card title="Reference — dominant variant" subtitle={reference.join(' → ')} glyph="✓">
                <div className="grid metrics">
                  <Metric label="Sequence coverage" value={fmt.percent(conformanceResult.fitness)} detail={`${conformanceResult.exact} exact cases`} />
                  <Metric label="Token replay" value={fmt.percent(conformanceResult.token)} detail={`${conformanceResult.missing} missing · ${conformanceResult.remaining} remaining`} />
                  <Metric label="Deviating" value={`${conformanceResult.total - conformanceResult.exact}`} detail={`of ${conformanceResult.total}`} />
                </div>
                <p className="subtle">Missing: {conformanceResult.missingActivities.join(' · ') || 'none'}</p>
                <p className="subtle">Extra: {conformanceResult.extraActivities.join(' · ') || 'none'}</p>
                <Note>Sequence coverage and token replay answer different questions; neither is a quality score.</Note>
              </Card>
            </div>
          )}

          {tab === 'insights' && (
            <div className="mining-tab">
              <Card title="Root cause — slow cases" subtitle="Attribute values correlated with longer cycles." glyph="◎">
                {causes.length === 0 ? <p className="subtle">No attribute has enough cases to compare.</p> : (
                  <div className="grid two wide">
                    {causes.slice(0, 6).map(cause => (
                      <div key={cause.id} className="insight-card">
                        <div className="row-meta"><Chip>{cause.dimension}</Chip><strong>{cause.value}</strong></div>
                        <div className="row-sub">{cause.cases} cases · {fmt.minutes(cause.cycle)} average</div>
                      </div>
                    ))}
                  </div>
                )}
              </Card>
              <Card title="Handovers" subtitle="Role pairs and average wait." glyph="⇄">
                <table className="table compact"><tbody>
                  {mined.edges.slice(0, 8).map(edge => <tr key={`${edge.from}-${edge.to}`}><td>{edge.from} → {edge.to}</td><td className="num">{edge.count}×</td><td className="num">{fmt.minutes(edge.wait)}</td></tr>)}
                </tbody></table>
              </Card>
            </div>
          )}

          {tab === 'simulate' && (
            <div className="mining-tab">
              <div className="grid two wide">
                <Card title="What if?" subtitle="Automate or remove steps; reduce repeat waits." glyph="⌘">
                  {mined.activities.slice(0, 8).map(activity => (
                    <div key={activity.name} className="sim-row">
                      <span>{activity.name}</span>
                      <label className="tiny"><input type="checkbox" checked={automate.has(activity.name)} onChange={e => setAutomate(next => { const copy = new Set(next); e.target.checked ? copy.add(activity.name) : copy.delete(activity.name); return copy })} /> Automate</label>
                      <label className="tiny"><input type="checkbox" checked={remove.has(activity.name)} onChange={e => setRemove(next => { const copy = new Set(next); e.target.checked ? copy.add(activity.name) : copy.delete(activity.name); return copy })} /> Remove</label>
                    </div>
                  ))}
                  <label className="tiny">Rework reduction {fmt.percent(reworkReduction)}<input type="range" min={0} max={1} step={0.1} value={reworkReduction} onChange={e => setReworkReduction(Number(e.target.value))} /></label>
                  <label className="tiny">Wait reduction {fmt.percent(waitReduction)}<input type="range" min={0} max={1} step={0.1} value={waitReduction} onChange={e => setWaitReduction(Number(e.target.value))} /></label>
                </Card>
                <div className="grid metrics">
                  <Metric label="Projected median" value={fmt.minutes(simulation.projected)} detail={`baseline ${fmt.minutes(simulation.baseline)}`} />
                  <Metric label="Saved per case" value={fmt.minutes(simulation.saved)} detail={`${simulation.affected} cases affected`} />
                  <Metric label="Hours / 1,000" value={`${Math.round(simulation.saved * 1000 / 60)} h`} detail="Estimate, not a validated saving" />
                </div>
              </div>
              <Note>This is a wait arithmetic on observed cases, not a capacity model. Validate before promising a saving.</Note>
            </div>
          )}
        </div>
      ) : (
        <div className="capture-view">
          <Card title="Task capture" subtitle="Desktop-only, opt-in and local." glyph="◉">
            <p className="subtle capture-copy">The browser cannot observe other applications. Capture lives in the macOS app: app usage, optional window titles, local screenshots, and keystroke/click counts (never content).</p>
            <Note>The web workbench consumes imported event logs; it never asks for screen-recording or accessibility permission.</Note>
          </Card>
        </div>
      )}
    </>
  )
}
