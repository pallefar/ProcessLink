import { useApp } from '../App'
import { Card, Chip, Empty, KV, Meter, Note, PageHead, routeTone } from '../components/ui'
import { evaluate, fmt, recommendMethod, scoreOpportunity } from '../domain/rules'
import { METHOD_TITLE, ROUTE_DETAIL, WASTE_LABEL } from '../domain/labels'

export default function Opportunities() {
  const { opportunities, processes, selectedOpportunity, selectOpportunity } = useApp()
  const ranked = [...opportunities].sort((a, b) => scoreOpportunity(b).total - scoreOpportunity(a).total)
  const opportunity = ranked.find(o => o.id === selectedOpportunity) ?? ranked[0]

  return (
    <>
      <PageHead title="Opportunities" subtitle="The prioritized pipeline: what is worth doing, why this route, what evidence supports it, and what a human must decide." />
      {!opportunity ? <Empty title="No opportunities" detail="Promote a discovered process to create the first one." /> : (
        <div className="split">
          <div className="list-pane">
            <div className="pane-head"><strong>{ranked.length} opportunities</strong><span className="tiny" style={{ marginLeft: 'auto' }}>score</span></div>
            <div className="scroll-list" role="listbox" aria-label="Opportunities">
              {ranked.map((item, index) => {
                const process = processes.find(p => p.id === item.processId)
                const guarded = !process || process.status !== 'discovered'
                return (
                  <button key={item.id} className="row" role="option" aria-selected={item.id === opportunity.id}
                    onClick={() => selectOpportunity(item.id)} style={{ alignItems: 'flex-start' }}>
                    <span className="tiny" style={{ width: 14, paddingTop: 2 }}>{index + 1}</span>
                    <span style={{ minWidth: 0 }}>
                      <div className="title">{item.title}</div>
                      <div className="sub">{item.processName} · {item.site}</div>
                      <div className="rowflex" style={{ marginTop: 4 }}>
                        <Chip tone={routeTone(item.route)}>{item.route}</Chip>
                        {item.statutory && <Chip tone="blue">Human control</Chip>}
                        {guarded && <Chip tone="red">Guarded</Chip>}
                      </div>
                    </span>
                    <span className="right">
                      <div style={{ fontSize: 13, fontWeight: 600 }}>{Math.round(scoreOpportunity(item).total)}</div>
                      <div className="tiny">{guarded ? 'hidden' : fmt.hoursPerYear(item.hours)}</div>
                    </span>
                  </button>
                )
              })}
            </div>
          </div>
          <div className="detail-pane">
            <OpportunityDetail id={opportunity.id} />
          </div>
        </div>
      )}
    </>
  )
}

function OpportunityDetail({ id }: { id: string }) {
  const { opportunities, processes, policy, promote, notify } = useApp()
  const opportunity = opportunities.find(o => o.id === id)
  if (!opportunity) return <Empty title="Not found" detail="This opportunity is no longer in the pipeline." />
  const process = processes.find(p => p.id === opportunity.processId)
  const guarded = !process || process.status !== 'discovered'
  const score = scoreOpportunity(opportunity)
  const recommendation = recommendMethod(opportunity.waste, opportunity.route, opportunity.statutory)

  if (guarded) {
    const reason = process
      ? evaluate({ groupSize: process.people, classification: process.classification, destination: 'knowledgeGraph', purpose: 'processImprovement', policy }).reason
      : 'The source process is missing from the graph.'
    return (
      <div className="stack">
        <h2 style={{ margin: 0, fontSize: 18 }}>{opportunity.title}</h2>
        <div className="rowflex"><Chip tone="red">Guarded</Chip><Chip>{opportunity.processName}</Chip><Chip>{opportunity.site}</Chip></div>
        <Card title="Blocked by the privacy guard" subtitle="This opportunity cannot be promoted." glyph="⛨">
          <p className="muted">{reason}</p>
          <KV items={[
            ['Process', opportunity.processName],
            ['Status', process?.status ?? 'missing'],
            ['Reason', process?.statusReason ?? 'Unknown'],
          ]} />
          <Note>The record stays visible so the refusal is auditable. Its numbers are not computed, exported, or sent to a model.</Note>
        </Card>
      </div>
    )
  }

  return (
    <div className="stack">
      <div>
        <div className="rowflex" style={{ alignItems: 'baseline' }}>
          <h2 style={{ margin: 0, fontSize: 18 }}>{opportunity.title}</h2>
          <div className="spacer" />
          <Chip>{opportunity.status}</Chip>
        </div>
        <div className="rowflex" style={{ marginTop: 8 }}>
          <Chip tone="blue">{opportunity.processName}</Chip>
          <Chip>{opportunity.site}</Chip>
          <Chip tone={routeTone(opportunity.route)}>{WASTE_LABEL[opportunity.waste]}</Chip>
          <Chip>{METHOD_TITLE[opportunity.method]}</Chip>
          <Chip tone={opportunity.confidence >= 0.85 ? 'green' : 'orange'}>{fmt.percent(opportunity.confidence)} confidence</Chip>
        </div>
      </div>

      <Card title="Why it ranks here" subtitle="The arithmetic is shown, not hidden." glyph="ƒ">
        <div style={{ display: 'grid', gridTemplateColumns: '96px minmax(0, 1fr)', gap: 20, alignItems: 'center' }}>
          <div style={{ textAlign: 'center' }}>
            <div style={{ fontSize: 40, fontWeight: 680, lineHeight: 1, fontVariantNumeric: 'tabular-nums' }}>{Math.round(score.total)}</div>
            <div className="tiny">of 100</div>
          </div>
          <div className="stack" style={{ gap: 10 }}>
            <Meter label="Impact (hours + error reduction)" value={score.impact} tone="orange" />
            <Meter label="Ease (effort estimate)" value={score.ease} />
            <Meter label="Hoshin alignment" value={score.alignment} tone="purple" />
            <Meter label="Automation suitability" value={score.automation} tone="teal" />
            {score.riskPenalty > 0 && <Meter label="Risk penalty" value={score.riskPenalty * 5} valueText={`−${Math.round(score.riskPenalty)} pts`} tone="red" />}
          </div>
        </div>
        <ul className="tiny" style={{ margin: '12px 0 0', paddingLeft: 16 }}>
          {score.reasoning.map(line => <li key={line}>{line}</li>)}
        </ul>
      </Card>

      <div className="grid two">
        <Card title="Recommended path" subtitle="Eliminate → simplify → standardize → automate." glyph="→">
          <div className="rowflex" style={{ marginBottom: 8 }}>
            <Chip tone={routeTone(opportunity.route)}>{opportunity.route}</Chip>
          </div>
          <p className="muted" style={{ marginTop: 0 }}>{ROUTE_DETAIL[opportunity.route]}</p>
          <div className="divider" />
          <strong style={{ fontSize: 12 }}>{METHOD_TITLE[recommendation.method]}</strong>
          <p className="muted">{recommendation.reason}</p>
          {opportunity.statutory && <Note glyph="✋">Statutory or human-only control: automation is excluded by the rule, not by reviewer choice.</Note>}
        </Card>
        <Card title="Evidence" subtitle="Each figure traces to a discovery object or a KG node." glyph="▤">
          <KV items={[
            ['Annual effort', fmt.hoursPerYear(opportunity.hours)],
            ['Error reduction', `${Math.round(opportunity.errorReduction)}%`],
            ['Effort estimate', `${Math.round(opportunity.effortWeeks)} weeks`],
            ['Risk', `${opportunity.risk}/5`],
            ['Hoshin alignment', `${opportunity.alignment}/5`],
            ['Discovery id', <span className="mono">{opportunity.processId}</span>],
            ['KG node', <span className="mono">{opportunity.kgId}</span>],
            ['Owner role', opportunity.owner],
          ]} />
          <div className="divider" />
          <p className="tiny" style={{ margin: 0, whiteSpace: 'pre-wrap' }}>{opportunity.rationale}</p>
        </Card>
      </div>

      <div className="rowflex">
        <button className="btn primary" onClick={() => promote(opportunity)} disabled={opportunity.status === 'promoted'}>Start initiative</button>
        <button className="btn" onClick={() => promote(opportunity)} disabled={opportunity.status === 'promoted'}>Draft A3</button>
        <button className="btn" onClick={() => notify('Opportunity deferred', opportunity.title)}>Defer</button>
        <span className="tiny" style={{ marginLeft: 'auto', maxWidth: 360 }}>
          A promotion creates a local initiative and proposes a KG node. It never deploys an automation or changes a production system.
        </span>
      </div>
    </div>
  )
}
