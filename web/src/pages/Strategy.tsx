import { useEffect, useState } from 'react'
import { Card, Chip, Metric } from '../components/ui'
import { osGet, type LiveProjects, type VisionRoadmap } from '../domain/osBridge'
import { INITIATIVES } from '../domain/data'

const VISION = {
  functionName: 'Operations',
  title: 'Right first time, end to end',
  statement: 'Make every order and invoice flow right the first time — designed around the customer, simplified before it is automated, and measured end to end.',
  horizon: 'FY2026',
  owner: 'COO',
}

const VALUES = [
  { id: 'customer', name: 'Customer first', statement: "Start with the customer's wait, not our queue.", behaviour: 'Every improvement states whose wait it removes.' },
  { id: 'right', name: 'Right first time', statement: 'Fix the cause, not the exception.', behaviour: 'Countermeasures remove a defect source, not a symptom.' },
  { id: 'simplify', name: 'Simplify before automate', statement: 'Remove work before buying a robot.', behaviour: 'An automation case must show the simpler path was tested.' },
  { id: 'people', name: 'People in the loop', statement: 'Automation drafts; a named human decides.', behaviour: 'No automatic send, release or performance decision.' },
]

const BETS = [
  { id: 'o2c', title: 'Order-to-cash velocity', detail: 'Remove duplicate checks and handoffs between order intake and cash.', owner: 'COO', kpi: 'o2c', values: ['customer', 'right'] },
  { id: 'finance', title: 'Frictionless finance', detail: 'One exception language, a clean close, and no rework loop.', owner: 'Finance Director', kpi: 'invoice', values: ['right', 'customer'] },
  { id: 'digital', title: 'Digital operations at the desk', detail: 'Give people one status view and remove re-keying before adding agents.', owner: 'CI Manager', kpi: 'manual', values: ['simplify', 'people'] },
  { id: 'standard', title: 'Standard work that sticks', detail: 'Make the best known way the default, with a named owner and an audit.', owner: 'Ops Excellence Lead', kpi: 'adherence', values: ['right', 'people'] },
]

const KPIS = [
  { id: 'o2c', name: 'Order-to-cash lead time', unit: 'days', baseline: 12, current: 11, target: 9, direction: 'lower', cadence: 'Weekly', source: 'Discovery timestamps + SAP', bet: 'o2c' },
  { id: 'invoice', name: 'Invoice exception rework', unit: '%', baseline: 34, current: 9, target: 10, direction: 'lower', cadence: 'Weekly', source: 'SAP exception log', bet: 'finance' },
  { id: 'manual', name: 'Manual touches per order', unit: 'touches', baseline: 7, current: 6, target: 4, direction: 'lower', cadence: 'Monthly', source: 'Task capture + event log', bet: 'digital' },
  { id: 'case', name: 'Case handling minutes', unit: 'min', baseline: 38, current: 34, target: 26, direction: 'lower', cadence: 'Weekly', source: 'ServiceNow + Salesforce', bet: 'digital' },
  { id: 'adherence', name: 'Standard-work adherence', unit: '%', baseline: 68, current: 78, target: 85, direction: 'higher', cadence: 'Monthly', source: 'Audit sample', bet: 'standard' },
]

const LINKS: Record<string, { bet: string; kpi: string; values: string[]; expected: string }> = {
  'ini-codes': { bet: 'finance', kpi: 'invoice', values: ['right', 'customer'], expected: 'Exception rework moves toward the 10% target.' },
  'ini-pricing': { bet: 'o2c', kpi: 'o2c', values: ['simplify', 'right'], expected: 'Order-to-cash lead time moves toward 9 days.' },
  'ini-agent': { bet: 'digital', kpi: 'case', values: ['people', 'simplify'], expected: 'Case handling minutes move toward 26.' },
  'ini-credit': { bet: 'standard', kpi: 'adherence', values: ['right', 'people'], expected: 'Adherence moves toward the 85% target.' },
  'ini-5s': { bet: 'digital', kpi: 'manual', values: ['simplify', 'people'], expected: 'Manual touches move from 6 toward 4.' },
  'ini-rpa': { bet: 'digital', kpi: 'manual', values: ['simplify', 'people'], expected: 'Manual touches move from 6 toward 4.' },
}

const progress = (kpi: typeof KPIS[number]) => Math.min(1, Math.max(0, (kpi.current - kpi.baseline) / (kpi.target - kpi.baseline)))
const onTrack = (kpi: typeof KPIS[number]) => kpi.direction === 'lower' ? kpi.current <= kpi.target : kpi.current >= kpi.target
const valueName = (id: string) => VALUES.find(v => v.id === id)?.name ?? id
const betName = (id: string) => BETS.find(b => b.id === id)?.title ?? 'Not linked'
const kpiName = (id: string) => KPIS.find(k => k.id === id)?.name ?? 'Not linked'

export default function Strategy() {
  const linked = INITIATIVES.filter(i => LINKS[i.id])
  const [roadmap, setRoadmap] = useState<VisionRoadmap | null>(null)
  const [projects, setProjects] = useState<LiveProjects | null>(null)
  const [importedBets, setImportedBets] = useState<Array<{ id: string; title: string }>>(() => {
    try { return JSON.parse(localStorage.getItem('processlink.importedBets') || '[]') as Array<{ id: string; title: string }> } catch { return [] }
  })
  useEffect(() => {
    void Promise.all([osGet<VisionRoadmap>('/api/vision/roadmap'), osGet<LiveProjects>('/api/projects')]).then(([road, proj]) => {
      setRoadmap(road); setProjects(proj)
    })
  }, [])
  const onTarget = KPIS.filter(onTrack).length

  return (
    <div className="stack strategy-page">
      <div className="page-head">
        <div>
          <h2 className="page-title">Strategy</h2>
          <p className="page-sub">The function vision, the few bets that matter, the KPIs that prove movement, and the values that constrain how we improve.</p>
        </div>
        <div className="row-meta">
          <Chip tone="green">{linked.length}/{INITIATIVES.length} initiatives linked</Chip>
          <Chip>{VISION.horizon}</Chip>
        </div>
      </div>

      <Card title="Live OS context" subtitle="Vision roadmap and Atlas project registry, read through the OS session." glyph="◉">
        <div className="row-meta" style={{ marginBottom: 6 }}>
          <Chip tone={roadmap ? 'purple' : undefined}>{roadmap ? `${roadmap.records.length} roadmap items` : 'Vision unavailable'}</Chip>
          <Chip tone={projects ? 'green' : undefined}>{projects ? `${projects.projects.length} Atlas projects` : 'Atlas unavailable'}</Chip>
        </div>
        {roadmap?.records.slice(0, 4).map(item => (
          <div className="row-meta" key={item.id} style={{ justifyContent: 'space-between', padding: '3px 0' }}>
            <span>{item.body?.title ?? item.id}</span><span className="tiny">{item.body?.stage ?? ''}</span>
            <button className="btn small" onClick={() => {
              const title = item.body?.title ?? item.id
              setImportedBets(current => {
                if (current.some(value => value.id === item.id)) return current
                const next = [...current, { id: item.id, title }]
                localStorage.setItem('processlink.importedBets', JSON.stringify(next))
                return next
              })
            }}>Import</button>
          </div>
        ))}
        {importedBets.length > 0 && <div className="tiny" style={{ marginTop: 6 }}>Imported bets: {importedBets.map(item => item.title).join(' · ')}</div>}
        {projects && <div className="tiny" style={{ marginTop: 4 }}>{projects.projects.slice(0, 5).map(project => project.label).join(' · ')}</div>}
      </Card>

      <Card title="Function vision" subtitle={`${VISION.functionName} · owned by ${VISION.owner}`} glyph="◎">
        <h3 className="strategy-vision-title">{VISION.title}</h3>
        <p className="strategy-vision-copy">{VISION.statement}</p>
        <div className="row-meta">
          <Chip>{VISION.horizon}</Chip>
          <Chip>Function: {VISION.functionName}</Chip>
        </div>
        <p className="subtle strategy-note">A human-owned statement. Linking an initiative does not prove impact; the KPI and before/after evidence do.</p>
      </Card>

      <div className="grid metrics">
        <Metric label="Strategic bets" value={String(BETS.length)} detail={`${BETS.length} active`} />
        <Metric label="KPIs on target" value={`${onTarget}/${KPIS.length}`} detail="Progress against agreed targets" />
        <Metric label="Linked initiatives" value={String(linked.length)} detail={linked.length === INITIATIVES.length ? 'Portfolio fully traceable' : 'Needs a link'} />
        <Metric label="Values" value={String(VALUES.length)} detail="Behavioural guardrails" />
      </div>

      <div className="grid two wide">
        <Card title="Strategic bets" subtitle="Stable choices; initiatives change underneath them." glyph="◎">
          <div className="strategy-bets">
            {BETS.map(bet => {
              const kpi = KPIS.find(k => k.id === bet.kpi)!
              const count = INITIATIVES.filter(i => LINKS[i.id]?.bet === bet.id).length
              return (
                <div key={bet.id} className="strategy-bet">
                  <div className="strategy-bet-head"><strong>{bet.title}</strong><Chip tone="green">Active</Chip><span className="subtle">{count === 1 ? '1 initiative' : `${count} initiatives`}</span></div>
                  <p className="subtle">{bet.detail}</p>
                  <div className="row-meta"><span className="tiny">Owner {bet.owner}</span><span className="tiny">· {kpi.name}</span><span className="spacer" />{bet.values.map(v => <Chip key={v} tone="blue">{valueName(v)}</Chip>)}</div>
                  <div className="strategy-progress"><span style={{ width: `${progress(kpi) * 100}%` }} data-track={onTrack(kpi)} /></div>
                  <div className="strategy-progress-meta"><span>{Math.round(progress(kpi) * 100)}% to target</span><span>{kpi.cadence}</span></div>
                </div>
              )
            })}
          </div>
        </Card>

        <Card title="Values" subtitle="The countermeasure has to respect these, not just hit the number." glyph="✓">
          <div className="strategy-values">
            {VALUES.map(value => (
              <div key={value.id}>
                <strong>{value.name}</strong>
                <p className="subtle">{value.statement}</p>
                <p className="tiny">{value.behaviour}</p>
              </div>
            ))}
          </div>
        </Card>
      </div>

      <Card title="KPIs" subtitle="A KPI without a definition, baseline, current value and target is a slogan." glyph="↗">
        <table className="table compact strategy-kpis">
          <thead><tr><th>KPI</th><th className="num">Baseline</th><th className="num">Current</th><th className="num">Target</th><th>Progress</th><th>Source</th></tr></thead>
          <tbody>
            {KPIS.map(kpi => (
              <tr key={kpi.id}>
                <td><strong>{kpi.name}</strong><div className="row-sub">{betName(kpi.bet)}</div></td>
                <td className="num">{kpi.baseline}{kpi.unit === '%' ? '%' : ` ${kpi.unit}`}</td>
                <td className="num"><strong>{kpi.current}{kpi.unit === '%' ? '%' : ` ${kpi.unit}`}</strong></td>
                <td className="num">{kpi.target}{kpi.unit === '%' ? '%' : ` ${kpi.unit}`}</td>
                <td><div className="strategy-progress"><span style={{ width: `${progress(kpi) * 100}%` }} data-track={onTrack(kpi)} /></div><div className="strategy-progress-meta"><span>{Math.round(progress(kpi) * 100)}%</span><span>{onTrack(kpi) ? 'On target' : kpi.direction === 'lower' ? 'Lower is better' : 'Higher is better'}</span></div></td>
                <td className="row-sub">{kpi.source}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>

      <Card title="Initiative alignment" subtitle="Every initiative needs a bet, a KPI and at least one value." glyph="⚭">
        <table className="table compact strategy-links">
          <thead><tr><th>Initiative</th><th>Strategic bet</th><th>KPI</th><th>Values</th><th>Expected change</th></tr></thead>
          <tbody>
            {INITIATIVES.map(initiative => {
              const link = LINKS[initiative.id]
              return (
                <tr key={initiative.id}>
                  <td><strong>{initiative.title}</strong><div className="row-sub">{initiative.processName}</div></td>
                  <td>{link ? betName(link.bet) : <Chip tone="orange">Not linked</Chip>}</td>
                  <td>{link ? kpiName(link.kpi) : <Chip tone="orange">Not linked</Chip>}</td>
                  <td>{link ? link.values.map(valueName).join(' · ') : '—'}</td>
                  <td className="row-sub">{link?.expected ?? 'Select a bet, KPI and value.'}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </Card>

      <p className="subtle">This web view is read-only for strategy. Edit the vision, KPI current value and initiative links in the macOS app.</p>
    </div>
  )
}
