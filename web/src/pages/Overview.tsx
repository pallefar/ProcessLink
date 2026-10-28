import { useApp } from '../App'
import { Card, Chip, Metric, Note, PageHead, Meter, routeTone } from '../components/ui'
import { canDisplay, fmt, initiativeLine, savingsConflicts, savingsTotal, scoreOpportunity } from '../domain/rules'

export default function Overview() {
  const { processes, opportunities, initiatives, governance, navigate, selectOpportunity, policy, selectInitiative, meetings, blocks, selectMeeting } = useApp()
  const visible = processes.filter(p => p.status === 'discovered' && canDisplay(p, policy))
  const ranked = opportunities
    .filter(o => visible.some(p => p.id === o.processId) && o.status !== 'deferred')
    .sort((a, b) => scoreOpportunity(b).total - scoreOpportunity(a).total)
  const lines = initiatives.map(initiativeLine)
  const totals = {
    estimated: savingsTotal(lines, 'estimated'),
    committed: savingsTotal(lines, 'committed'),
    validated: savingsTotal(lines, 'validated'),
  }
  const conflicts = savingsConflicts(lines)
  const openInitiatives = initiatives.filter(i => i.savingsStage !== 'validated').length

  return (
    <>
      <PageHead
        title="Value overview"
        subtitle="in-house discovery, turned into prioritized TEOA work — every number traceable, nothing presented as validated until it is."
      />

      <div className="grid metrics">
        <Metric glyph="◉" label="Discovered effort" value={fmt.hoursPerYear(visible.reduce((sum, p) => sum + p.annualHours, 0))} detail={`${visible.length} processes in scope`} />
        <Metric glyph="◈" label="Opportunity pipeline" value={fmt.hoursPerYear(ranked.reduce((sum, o) => sum + o.hours, 0))} detail={`${ranked.length} opportunities, estimate only`} />
        <Metric glyph="✓" label="Validated savings" value={fmt.hoursPerYear(totals.validated)} detail={`${fmt.money(totals.validated)} at €${52}/h`} />
        <Metric glyph="⚑" label="Open initiatives" value={String(openInitiatives)} detail={`${initiatives.length} total in the portfolio`} />
      </div>

      <div className="grid two">
        <Card title="Priority queue" subtitle="Ranked by impact, ease, alignment and confidence." glyph="≡">
          <div className="stack" style={{ gap: 0 }}>
            {ranked.slice(0, 4).map((opportunity, index) => {
              const score = scoreOpportunity(opportunity)
              return (
                <button
                  key={opportunity.id}
                  className="row"
                  onClick={() => { selectOpportunity(opportunity.id); navigate('opportunities') }}
                  style={{ paddingTop: 10, paddingBottom: 10, borderTop: index ? '1px solid var(--border)' : undefined, borderRadius: 0 }}
                >
                  <span style={{ fontSize: 18, fontWeight: 650, width: 34, fontVariantNumeric: 'tabular-nums' }}>{Math.round(score.total)}</span>
                  <span style={{ minWidth: 0 }}>
                    <div className="title">{opportunity.title}</div>
                    <div className="sub">{opportunity.processName} · {opportunity.site}</div>
                  </span>
                  <span className="right">
                    <div>{fmt.hoursPerYear(opportunity.hours)}</div>
                    <Chip tone={routeTone(opportunity.route)}>{opportunity.route}</Chip>
                  </span>
                </button>
              )
            })}
          </div>
        </Card>

        <div>
          <Card title="Savings pipeline" subtitle="One claim per process and waste type." glyph="▤">
            {(['estimated', 'committed', 'validated'] as const).map(stage => {
              const value = totals[stage]
              const max = Math.max(totals.estimated, totals.committed, totals.validated, 1)
              return (
                <div key={stage} style={{ marginBottom: 12 }}>
                  <Meter label={stage[0]!.toUpperCase() + stage.slice(1)} value={(value / max) * 100}
                    valueText={fmt.hours(value)}
                    tone={stage === 'validated' ? 'green' : stage === 'committed' ? undefined : 'orange'} />
                  <div className="tiny" style={{ marginTop: 3 }}>
                    {stage === 'estimated' ? 'Calculated from mined data. Not a claim.'
                      : stage === 'committed' ? 'An owner and a target date have signed up.'
                        : 'Before/after evidence checked by a named validator.'}
                  </div>
                </div>
              )
            })}
            {conflicts.length > 0 && (
              <Note glyph="▲">{conflicts.length} possible double count{conflicts.length === 1 ? '' : 's'} across initiatives. Resolve before the roll-up.</Note>
            )}
          </Card>

        </div>
      </div>

      <div className="grid three">
        <Card title="Evidence freshness" subtitle="Maps and opportunities are only as good as their last local refresh." glyph="◷">
          <div className="stack" style={{ gap: 8 }}>
            {[...visible].sort((a, b) => b.staleDays - a.staleDays).slice(0, 4).map(process => (
              <div key={process.id} className="between">
                <span>{process.name}</span>
                <span className={process.staleDays > 14 ? 'chip' : 'tiny'} data-tone={process.staleDays > 14 ? 'orange' : undefined}>
                  {process.staleDays > 14 ? `${process.staleDays} days — stale` : `${process.staleDays} day${process.staleDays === 1 ? '' : 's'} old`}
                </span>
              </div>
            ))}
            <div className="tiny">Last local refresh 3 days ago · 7 processes · 5 captures</div>
          </div>
        </Card>

        <Card title="Launch posture" subtitle="Nothing is production-ready until the checklist is signed." glyph="⛨">
          <div className="stack" style={{ gap: 8 }}>
            {governance.filter(item => item.status !== 'done').slice(0, 3).map(item => (
              <div key={item.id} className="between">
                <div>
                  <div style={{ fontSize: 12 }}>{item.title}</div>
                  <div className="tiny">{item.owner}</div>
                </div>
                <Chip tone={item.status === 'blocked' ? 'red' : item.status === 'inProgress' ? 'blue' : undefined}>
                  {item.status === 'inProgress' ? 'In progress' : item.status === 'blocked' ? 'Blocked' : 'Not started'}
                </Chip>
              </div>
            ))}
            <button className="btn small" onClick={() => navigate('governance')} style={{ alignSelf: 'flex-start' }}>Open the checklist</button>
          </div>
        </Card>
        <Card title="Validated at a glance" subtitle="The only number that may be called a saving." glyph="✓">
          <div className="stack" style={{ gap: 10 }}>
            <div style={{ fontSize: 28, fontWeight: 650, fontVariantNumeric: 'tabular-nums' }}>{fmt.hours(totals.validated)}</div>
            <div className="muted">{fmt.money(totals.validated)} per year at €52/hour</div>
            <div className="rowflex">
              {initiatives.filter(i => i.savingsStage === 'validated').map(initiative => (
                <button key={initiative.id} className="chip" data-tone="green" onClick={() => { selectInitiative(initiative.id); navigate('improvements') }}>
                  {initiative.title}
                </button>
              ))}
            </div>
            <Note glyph="⛨">A saving becomes a claim only with a named validator and before/after evidence. Everything else stays an estimate.</Note>
          </div>
        </Card>
      </div>

      <Card title="Meetings & actions" subtitle="Notes become decisions; decisions become work." glyph="◫">
        <div className="grid two" style={{ gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)' }}>
          <div>
            <div className="tiny" style={{ marginBottom: 6 }}>Recent pages</div>
            {[...meetings].sort((a, b) => b.date.localeCompare(a.date)).slice(0, 2).map(meeting => (
              <button key={meeting.id} className="row" style={{ padding: 4 }}
                onClick={() => { selectMeeting(meeting.id); navigate('meetings') }}>
                <span style={{ minWidth: 0 }}>
                  <div className="title" style={{ fontSize: 12 }}>{meeting.title}</div>
                  <div className="tiny">{new Date(meeting.date).toLocaleDateString('en-GB')} · {meeting.owner}</div>
                </span>
              </button>
            ))}
          </div>
          <div>
            <div className="tiny" style={{ marginBottom: 6 }}>Open actions</div>
            {blocks.filter(b => b.kind === 'action' && !b.checked).slice(0, 2).map(item => (
              <div key={item.id} className="between" style={{ padding: '4px 0' }}>
                <span className="tiny" style={{ maxWidth: 240 }}>{item.text || 'Untitled action'}</span>
                <span className="tiny">{item.owner}</span>
              </div>
            ))}
            <button className="btn small" onClick={() => navigate('meetings')} style={{ marginTop: 6 }}>Open Meetings</button>
          </div>
        </div>
      </Card>
    </>
  )
}
