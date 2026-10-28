import { useState } from 'react'
import { useApp } from '../App'
import { Card, Chip, Note, PageHead } from '../components/ui'

export default function Ask() {
  const { answers, ask, clearAsk, suggestions, policy, selectNode, navigate } = useApp()
  const [draft, setDraft] = useState('')

  const send = () => {
    if (!draft.trim()) return
    ask(draft)
    setDraft('')
  }

  return (
    <div className="ask-page">
      <PageHead title="Ask the process" subtitle="Questions over KYP.ai discovery, the knowledge graph and TEOA work. Local provider by default; the hosted provider follows the same guard." />
      <div className="rowflex">
        <Chip tone="green">{policy.provider}</Chip>
        <Chip>Region {policy.region}</Chip>
        <Chip tone="green">Purpose: improvement only</Chip>
        <Chip>Groups ≥ {policy.minimumGroupSize}</Chip>
        <div className="spacer" />
        {answers.length > 0 && <button className="btn small" onClick={clearAsk}>Clear</button>}
      </div>

      {answers.length === 0 && (
        <>
          <div className="rowflex">
            {suggestions.map(suggestion => (
              <button key={suggestion} className="chip" onClick={() => ask(suggestion)}>{suggestion}</button>
            ))}
          </div>
          <Card title="What this assistant may and may not do" subtitle="The same rules as every other surface." glyph="⛨">
            <div className="stack" style={{ gap: 8 }}>
              {[
                'Reads only aggregated, permission-filtered facts from KYP.ai and the KG.',
                'Refuses individual performance questions and groups below the threshold.',
                'Masks personal-data patterns before a hosted AI call; local answers never leave this Mac.',
                'Never invents a number: a missing fact becomes a to-verify item, and a saving is labelled an estimate.',
                'Cites the KYP.ai object or KG node behind every figure.',
              ].map(line => <div key={line} className="rowflex"><span style={{ color: 'var(--green)' }}>✓</span><span className="muted">{line}</span></div>)}
            </div>
          </Card>
        </>
      )}

      <div className="chat">
        {answers.map(answer => (
          <div key={answer.id} className="stack">
            <div className="bubble-q">{answer.question}</div>
            <div className="answer">
              <div className="between">
                <h3>{answer.headline}</h3>
                <Chip tone={answer.confidence >= 0.8 ? 'green' : 'orange'}>{Math.round(answer.confidence * 100)}% confidence</Chip>
              </div>
              <p>{answer.body}</p>
              {answer.citations.length > 0 && (
                <div>
                  <div className="tiny" style={{ marginBottom: 4 }}>Sources</div>
                  <div className="citations">
                    {answer.citations.map(citation => (
                      <button key={`${citation.kind}-${citation.ref}`} className="citation" style={{ cursor: 'pointer' }}
                        onClick={() => { if (citation.kind === 'kg') { selectNode(citation.ref); navigate('graph') } }}>
                        {citation.kind === 'kg' ? 'KG' : citation.kind === 'kyp' ? 'KYP.ai' : citation.kind} · {citation.label}
                      </button>
                    ))}
                  </div>
                </div>
              )}
              {answer.toVerify.length > 0 && (
                <div>
                  <div className="tiny" style={{ marginBottom: 4, color: 'var(--orange)' }}>To verify</div>
                  {answer.toVerify.map(line => <div key={line} className="tiny">? {line}</div>)}
                </div>
              )}
            </div>
          </div>
        ))}
      </div>

      <div className="composer">
        <input
          aria-label="Ask about a process"
          placeholder="Ask about handoffs, rework, variants, a process or freshness…"
          value={draft}
          onChange={event => setDraft(event.target.value)}
          onKeyDown={event => { if (event.key === 'Enter') { event.preventDefault(); send() } }}
        />
        <button className="btn primary" onClick={send} disabled={!draft.trim()}>Ask</button>
      </div>
      <Note>Numbers trace to KYP.ai ids or KG nodes. Personal-data patterns are masked before any call. Estimates are not validated savings.</Note>
    </div>
  )
}
