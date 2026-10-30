import { useState } from 'react'
import { useApp } from '../App'
import { Card, Chip, Note, PageHead } from '../components/ui'
import { evaluate, scanPII, type PIIScan } from '../domain/rules'
import type { PrivacyDecision } from '../domain/types'

const GROUPS = ['Data protection', 'People', 'Accountability', 'AI & security']

export default function Governance() {
  const { governance, audit, policy, setPolicy, setGovernanceStatus, feedback } = useApp()
  const [demo, setDemo] = useState<{ title: string; decision: PrivacyDecision; pii?: PIIScan } | null>(null)
  const done = governance.filter(item => item.status === 'done').length
  const blocked = governance.filter(item => item.status === 'blocked').length

  const run = (title: string, make: () => { decision: PrivacyDecision; pii?: PIIScan }) => {
    const result = make()
    setDemo({ title, decision: result.decision, pii: result.pii })
  }

  return (
    <>
      <PageHead title="Governance" subtitle="Purpose limitation, group thresholds, classification, retention and the human gates. Nothing is production-ready until this list is signed."
        actions={<><Chip tone="green">{done}/{governance.length} done</Chip><Chip tone="red">{blocked} blocked</Chip><button className="btn small" onClick={() => {
          let product: unknown[] = []
          try { product = JSON.parse(localStorage.getItem('processlink.productfeedback.v1') || '[]') as unknown[] } catch { /* ignore */ }
          const payload = { schema: 'processlink-web-backup/1', exportedAt: new Date().toISOString(), feedback, productFeedback: product, importedBets: JSON.parse(localStorage.getItem('processlink.importedBets') || '[]'), agentPolicy: JSON.parse(localStorage.getItem('processlink.agent.policy.v1') || 'null') }
          const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' })
          const url = URL.createObjectURL(blob); const link = document.createElement('a')
          link.href = url; link.download = 'processlink-web-backup.json'; link.click(); URL.revokeObjectURL(url)
        }}>Export data</button></>} />

      <div className="grid two">
        <div className="stack">
          {GROUPS.map(group => {
            const items = governance.filter(item => item.group === group)
            if (items.length === 0) return null
            return (
              <Card key={group} title={group} subtitle={
                group === 'Data protection' ? 'DPIA, legal basis per country, retention.'
                  : group === 'People' ? 'Works council, transparency, capture scope.'
                    : group === 'Accountability' ? 'Who owns the data and the numbers.'
                      : 'Approved models, regions, and the guard.'
              } glyph="⛨">
                <div className="stack" style={{ gap: 0 }}>
                  {items.map(item => (
                    <div key={item.id} className="between" style={{ padding: '8px 0', borderTop: '1px solid var(--border)', alignItems: 'flex-start' }}>
                      <div style={{ minWidth: 0 }}>
                        <div style={{ fontSize: 12.5, fontWeight: 550 }}>{item.title}</div>
                        <div className="tiny">{item.detail}</div>
                        <div className="tiny" style={{ opacity: 0.8 }}>{item.owner}</div>
                      </div>
                      <div className="rowflex" style={{ flexShrink: 0 }}>
                        <select aria-label={`Status of ${item.title}`} value={item.status}
                          onChange={event => setGovernanceStatus(item.id, event.target.value as typeof item.status)}
                          style={{ border: '1px solid var(--border)', background: 'var(--panel-2)', borderRadius: 6, fontSize: 10.5, padding: '2px 4px' }}>
                          <option value="done">Done</option>
                          <option value="inProgress">In progress</option>
                          <option value="blocked">Blocked</option>
                          <option value="notStarted">Not started</option>
                        </select>
                      </div>
                    </div>
                  ))}
                </div>
              </Card>
            )
          })}
        </div>

        <div className="stack">
          <Card title="Try the guard" subtitle="Same code path as sync, export and every AI call." glyph="✋">
            <div className="stack" style={{ gap: 8 }}>
              <button className="btn" onClick={() => run('Restricted → AI gateway', () => ({
                decision: evaluate({ groupSize: 14, classification: 'restricted', destination: 'aiGateway', purpose: 'processImprovement', policy }),
              }))}>Send Restricted to the AI gateway</button>
              <button className="btn" onClick={() => run('4-person group → export', () => ({
                decision: evaluate({ groupSize: 4, classification: 'internal', destination: 'export', purpose: 'processImprovement', policy }),
              }))}>Export a 4-person group</button>
              <button className="btn" onClick={() => run('AI call with a PII sample', () => {
                const pii = scanPII('Please fix case EMP-4821 for anna.schmidt@example.com, IBAN DE44 5001 0517 5407 3249 31.')
                return {
                  pii,
                  decision: evaluate({ groupSize: 22, classification: 'internal', destination: 'aiGateway', purpose: 'processImprovement', piiFindings: pii.total, policy }),
                }
              })}>Call AI with a PII sample</button>
            </div>
            {demo && (
              <>
                <div className="divider" />
                <div className="rowflex">
                  <Chip>{demo.title}</Chip>
                  <Chip tone={demo.decision.allowed ? 'green' : 'red'}>{demo.decision.action}</Chip>
                </div>
                <p className="tiny" style={{ margin: '8px 0 4px' }}>{demo.decision.reason}</p>
                <div className="mono tiny">{demo.decision.rule}</div>
                {demo.pii && <div className="mono tiny" style={{ marginTop: 6, padding: 8, background: 'var(--panel-2)', borderRadius: 6 }}>{demo.pii.masked}</div>}
              </>
            )}
          </Card>

          <Card title="Policy" subtitle="The guard reads these values before every destination." glyph="⚙">
            <div className="field" style={{ marginBottom: 10 }}>
              <label htmlFor="group">Minimum group size: {policy.minimumGroupSize}</label>
              <input id="group" type="range" min={5} max={50} value={policy.minimumGroupSize}
                onChange={event => setPolicy({ ...policy, minimumGroupSize: Number(event.target.value) })} />
            </div>
            <div className="field" style={{ marginBottom: 10 }}>
              <label htmlFor="provider">AI provider</label>
              <select id="provider" value={policy.provider} onChange={event => setPolicy({ ...policy, provider: event.target.value })}>
                <option>Local (on device)</option>
                <option>Anthropic Claude · EU</option>
              </select>
            </div>
            <Note>The threshold is a works-council decision, not a developer preference. Changing it here changes every display, export and AI call in this session.</Note>
          </Card>

          <Card title="Where data goes" subtitle="The data-flow contract in one card." glyph="⇢">
            <div className="stack" style={{ gap: 8 }}>
              {[
                ['discovery', 'System of record. Aggregated facts only; no screenshots, keystrokes or person ids.', 'var(--accent)'],
                ['ProcessLink', 'Local store. Purpose-limited, permission-filtered, audit-logged.', 'var(--purple)'],
                ['Knowledge graph', 'Nodes and edges with provenance; writes are reviewable.', 'var(--teal)'],
                ['Maps · TEOA · DeckForge', 'Read the same nodes; edits become change proposals.', 'var(--orange)'],
                ['AI gateway', 'Optional, region-pinned, classification-gated, PII-masked. Local by default.', 'var(--red)'],
              ].map(([title, detail, colour]) => (
                <div key={title} style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
                  <span aria-hidden="true" style={{ width: 6, height: 6, borderRadius: 999, background: colour, marginTop: 6 }} />
                  <div>
                    <div style={{ fontSize: 11.5, fontWeight: 600 }}>{title}</div>
                    <div className="tiny">{detail}</div>
                  </div>
                </div>
              ))}
            </div>
          </Card>
        </div>
      </div>

      <Card title="Audit log" subtitle="Append-only in the product: syncs, queries, AI calls, approvals and exports." glyph="☰">
        <table className="ledger">
          <thead><tr><th>When</th><th>Action</th><th>Subject</th><th>Actor</th></tr></thead>
          <tbody>
            {audit.slice(0, 8).map(entry => (
              <tr key={entry.id}>
                <td className="muted">{new Date(entry.at).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</td>
                <td className="mono">{entry.action}</td>
                <td>{entry.subject}</td>
                <td className="muted">{entry.actor}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
    </>
  )
}
