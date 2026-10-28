import { useState } from 'react'
import { useApp } from '../App'
import { Card, Chip, Empty, KV, Metric, Note, PageHead } from '../components/ui'
import { GraphOverview } from '../components/GraphOverview'
import { KG_LABEL, PREDICATE_LABEL } from '../domain/labels'
import type { KGKind } from '../domain/types'

const KINDS: KGKind[] = ['process', 'step', 'application', 'role', 'site', 'valueStream', 'opportunity', 'initiative', 'savingsRecord', 'hoshinObjective', 'document', 'meeting', 'decision', 'action']

export default function Graph() {
  const { nodes, edges, selectedNode, selectNode, reviewNode, meetings, selectMeeting, navigate } = useApp()
  const [filter, setFilter] = useState<KGKind | 'all'>('all')
  const [search, setSearch] = useState('')
  const suggested = nodes.filter(node => node.review === 'suggested')
  const ordered = [...nodes].sort((a, b) => KINDS.indexOf(a.kind) - KINDS.indexOf(b.kind) || a.name.localeCompare(b.name))
  const visible = ordered.filter(node =>
    (filter === 'all' || node.kind === filter)
    && (!search.trim() || node.name.toLowerCase().includes(search.toLowerCase())
      || node.id.toLowerCase().includes(search.toLowerCase())))
  const node = allFind(nodes, selectedNode) ?? suggested[0] ?? visible[0]
  const edgeCount = (id: string) => edges.filter(edge => edge.from === id || edge.to === id).length

  const meetingFor = (nodeId: string) => {
    const node = nodes.find(n => n.id === nodeId)
    if (!node) return undefined
    if (node.kind === 'meeting') return meetings.find(m => m.kgId === nodeId)
    if (node.kind !== 'decision' && node.kind !== 'action') return undefined
    const edge = edges.find(e => e.from === nodeId && e.predicate === 'documentedIn')
    return meetings.find(m => m.kgId === edge?.to)
  }
  const orphans = nodes.filter(item => edgeCount(item.id) === 0).length

  return (
    <>
      <PageHead title="Knowledge Graph" subtitle="The shared semantic backbone. KYP.ai facts become nodes with provenance; ProcessLink proposes, a human confirms." />

      <div className="grid metrics">
        <Metric label="Nodes" value={String(nodes.length)} detail={`${KINDS.length} of 29 proposed types in use`} />
        <Metric label="Edges" value={String(edges.length)} detail="Provenance on every one" />
        <Metric label="Orphans" value={String(orphans)} detail={orphans === 0 ? 'Every node is connected' : 'Nodes with no relation'} />
        <Metric label="Uncertain matches" value={String(suggested.length)} detail="Never merged without a human" />
      </div>

      <Card title="Graph overview" subtitle="The working set, laid out by what it is: process, opportunity, initiative, meeting, objective." glyph="⬡"
        actions={<Chip>{nodes.length} nodes · {edges.length} edges</Chip>}>
        <GraphOverview nodes={nodes} edges={edges} selected={node?.id} onSelect={selectNode} />
      </Card>

      {suggested.length > 0 && (
        <Card title="Entity resolution queue" subtitle="Low-confidence matches are proposals. They stay separate until a human confirms or rejects them." glyph="?" >
          <div className="stack" style={{ gap: 0 }}>
            {suggested.map(item => {
              const targetEdge = edges.find(edge => edge.from === item.id && edge.predicate === 'variantOf')
              const target = targetEdge ? allFind(nodes, targetEdge.to) : undefined
              return (
                <div key={item.id} className="between" style={{ padding: '8px 0', borderTop: '1px solid var(--border)' }}>
                  <div>
                    <div style={{ fontSize: 12.5, fontWeight: 550 }}>{item.name}</div>
                    <div className="tiny">{item.note ?? 'Proposed by entity resolution.'}</div>
                  </div>
                  <div className="rowflex">
                    <Chip tone="orange">{Math.round(item.confidence * 100)}% · review</Chip>
                    {target && <button className="btn small" onClick={() => reviewNode(item.id, target.id)}>Merge into {target.name}</button>}
                    <button className="btn small" onClick={() => reviewNode(item.id)}>Keep separate</button>
                  </div>
                </div>
              )
            })}
          </div>
        </Card>
      )}

      <div className="grid two" style={{ gridTemplateColumns: '400px minmax(0, 1fr)' }}>
        <Card title="Nodes" subtitle="Filter by type." glyph="≡">
          <input value={search} onChange={event => setSearch(event.target.value)} placeholder="Search nodes, ids"
            aria-label="Search nodes"
            style={{ width: '100%', border: '1px solid var(--border)', background: 'var(--panel-2)', borderRadius: 6, padding: '4px 8px', fontSize: 11, marginBottom: 8 }} />
          <div className="rowflex" style={{ marginBottom: 10 }}>
            <select aria-label="Filter by node type" value={filter}
              onChange={event => setFilter(event.target.value as KGKind | 'all')}
              style={{ border: '1px solid var(--border)', background: 'var(--panel-2)', borderRadius: 6, padding: '3px 6px', fontSize: 11 }}>
              <option value="all">All types</option>
              {KINDS.map(kind => <option key={kind} value={kind}>{KG_LABEL[kind]}</option>)}
            </select>
            <span className="tiny">{visible.length} shown</span>
          </div>
          <div className="scroll-list" style={{ maxHeight: 420 }}>
            {visible.map(item => (
              <button key={item.id} className="row" aria-selected={item.id === node?.id} onClick={() => selectNode(item.id)}>
                <span className="tiny" style={{ width: 12 }}>{item.review === 'suggested' ? '?' : '•'}</span>
                <span style={{ minWidth: 0 }}>
                  <div className="title" style={{ fontSize: 12 }}>{item.name}</div>
                  <div className="tiny">{KG_LABEL[item.kind]} · {edgeCount(item.id)} edges</div>
                </span>
              </button>
            ))}
          </div>
        </Card>

        {node ? (
          <Card title={KG_LABEL[node.kind]} subtitle={node.name} glyph="⬡">
            <div className="rowflex" style={{ marginBottom: 10 }}>
              <Chip tone={node.review === 'suggested' ? 'orange' : 'green'}>{node.review === 'suggested' ? 'Needs review' : node.review}</Chip>
              <Chip tone={node.confidence >= 0.85 ? 'green' : 'orange'}>{Math.round(node.confidence * 100)}% confidence</Chip>
              {meetingFor(node.id) && (
                <button className="btn small" onClick={() => { selectMeeting(meetingFor(node.id)!.id); navigate('meetings') }}>Open meeting</button>
              )}
            </div>
            <KV items={[
              ['Node id', <span className="mono">{node.id}</span>],
              ['Source', node.source],
              ['Source id', <span className="mono">{node.sourceId}</span>],
              ['Valid from', new Date(node.validFrom).toLocaleDateString('en-GB')],
              ...(node.note ? [['Note', node.note] as [string, string]] : []),
            ]} />
            <div className="divider" />
            <strong style={{ fontSize: 12 }}>Relations</strong>
            <div className="stack" style={{ gap: 6, marginTop: 6 }}>
              {edges.filter(edge => edge.from === node.id || edge.to === node.id).map(edge => {
                const outgoing = edge.from === node.id
                const other = allFind(nodes, outgoing ? edge.to : edge.from)
                return (
                  <button key={`${edge.from}-${edge.predicate}-${edge.to}`} className="row" style={{ padding: 4 }}
                    onClick={() => selectNode(other?.id ?? node.id)}>
                    <span className="tiny" style={{ width: 112 }}>{outgoing ? PREDICATE_LABEL[edge.predicate] : `← ${PREDICATE_LABEL[edge.predicate]}`}</span>
                    <span>→</span>
                    <span style={{ fontSize: 12 }}>{other?.name ?? edge.to}</span>
                    <span className="right">{Math.round(edge.confidence * 100)}%</span>
                  </button>
                )
              })}
            </div>
            <Note>Every fact carries source, confidence and validity. Changes are proposals, not silent overwrites.</Note>
          </Card>
        ) : <Empty title="No node selected" detail="Pick a node from the list." />}
      </div>
    </>
  )
}

function allFind<T extends { id: string }>(items: T[], id: string | undefined): T | undefined {
  return items.find(item => item.id === id)
}
