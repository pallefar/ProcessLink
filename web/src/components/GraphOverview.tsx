import type { KGEdge, KGKind, KGNode } from '../domain/types'
import { KG_LABEL } from '../domain/labels'

const COLUMNS: Array<{ title: string; kinds: KGKind[] }> = [
  { title: 'Process', kinds: ['process'] },
  { title: 'Opportunity', kinds: ['opportunity'] },
  { title: 'Initiative', kinds: ['initiative'] },
  { title: 'Meetings & decisions', kinds: ['meeting', 'decision', 'action'] },
  { title: 'Objectives', kinds: ['hoshinObjective', 'savingsRecord'] },
]

const NODE_W = 156
const NODE_H = 36
const COL_W = 196
const TOP = 46
const ROW = 48

const tint = (kind: KGKind): string => {
  switch (kind) {
    case 'process': return 'var(--accent)'
    case 'opportunity': return 'var(--orange)'
    case 'initiative': return 'var(--purple)'
    case 'meeting': return 'var(--green)'
    case 'decision': return 'var(--orange)'
    case 'action': return 'var(--teal)'
    case 'hoshinObjective': return 'var(--purple)'
    case 'savingsRecord': return 'var(--green)'
    default: return 'var(--secondary)'
  }
}

export function GraphOverview({ nodes, edges, selected, onSelect }: {
  nodes: KGNode[]; edges: KGEdge[]; selected?: string; onSelect: (id: string) => void
}) {
  const columns = COLUMNS.map(column => ({
    ...column,
    nodes: nodes.filter(node => column.kinds.includes(node.kind)).slice(0, 7),
  }))
  const rows = Math.max(...columns.map(column => column.nodes.length), 1)
  const width = 24 + columns.length * COL_W
  const height = TOP + rows * ROW + 12
  const position = new Map<string, { x: number; y: number }>()
  columns.forEach((column, columnIndex) => {
    column.nodes.forEach((node, rowIndex) => {
      position.set(node.id, { x: 20 + columnIndex * COL_W, y: TOP + rowIndex * ROW })
    })
  })

  return (
    <div className="graph-canvas">
      <svg viewBox={`0 0 ${width} ${height}`} width="100%" height={height} role="img"
        aria-label={`Knowledge graph overview: ${columns.map(c => `${c.title} ${c.nodes.length}`).join(', ')}`}>
        {columns.map((column, index) => (
          <text key={column.title} x={20 + index * COL_W} y={22} className="graph-col-label">{column.title}</text>
        ))}
        {edges.map(edge => {
          const from = position.get(edge.from)
          const to = position.get(edge.to)
          if (!from || !to) return null
          const x1 = from.x + NODE_W
          const y1 = from.y + NODE_H / 2
          const x2 = to.x
          const y2 = to.y + NODE_H / 2
          const mid = (x1 + x2) / 2
          return <path key={`${edge.from}-${edge.predicate}-${edge.to}`} d={`M ${x1} ${y1} C ${mid} ${y1}, ${mid} ${y2}, ${x2} ${y2}`}
            fill="none" stroke="var(--secondary)" strokeOpacity={0.28} strokeWidth={1} />
        })}
        {columns.map((column, columnIndex) => column.nodes.map((node, rowIndex) => {
          const x = 20 + columnIndex * COL_W
          const y = TOP + rowIndex * ROW
          return (
            <g key={node.id} className="graph-node" role="button" tabIndex={0}
              aria-label={`${KG_LABEL[node.kind]}: ${node.name}`}
              onClick={() => onSelect(node.id)}
              onKeyDown={event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(node.id) } }}>
              <rect x={x} y={y} width={NODE_W} height={NODE_H} rx={8}
                data-selected={selected === node.id}
                style={{ fill: tint(node.kind), fillOpacity: selected === node.id ? 0.22 : 0.12, stroke: tint(node.kind), strokeOpacity: selected === node.id ? 0.9 : 0.35 }} />
              <text x={x + 9} y={y + 15} className="graph-node-title">{node.name.length > 23 ? `${node.name.slice(0, 22)}…` : node.name}</text>
              <text x={x + 9} y={y + 28} className="graph-node-sub">{KG_LABEL[node.kind]} · {Math.round(node.confidence * 100)}%</text>
            </g>
          )
        }))}
      </svg>
      <div className="graph-legend">
        <span><i style={{ background: 'var(--accent)' }} /> Process</span>
        <span><i style={{ background: 'var(--orange)' }} /> Opportunity</span>
        <span><i style={{ background: 'var(--purple)' }} /> Initiative</span>
        <span><i style={{ background: 'var(--green)' }} /> Meeting</span>
        <span><i style={{ background: 'var(--teal)' }} /> Action</span>
      </div>
    </div>
  )
}
