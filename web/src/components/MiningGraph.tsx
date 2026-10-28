import type { MinedProcess } from '../domain/mining'

export function MiningGraph({ mined, selected, onSelect }: {
  mined: MinedProcess; selected?: string; onSelect: (name: string) => void
}) {
  const order = [...new Set(mined.variants[0]?.path.split(' → ') ?? mined.activities.map(a => a.name))]
  for (const activity of mined.activities) if (!order.includes(activity.name)) order.push(activity.name)
  const positions = new Map<string, { x: number; y: number }>()
  order.forEach((name, index) => positions.set(name, { x: 30 + index * 180, y: 90 }))
  const width = Math.max(760, 30 + order.length * 180)
  const height = 260
  const maxEdge = Math.max(1, ...mined.edges.map(e => e.count))
  const activity = (name: string) => mined.activities.find(a => a.name === name)

  return (
    <div className="mining-graph">
      <svg viewBox={`0 0 ${width} ${height}`} width="100%" height={height} role="img" aria-label="Discovered process graph">
        <defs>
          <marker id="mg-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
            <path d="M 0 0 L 10 5 L 0 10 z" fill="var(--secondary)" />
          </marker>
        </defs>
        {mined.edges.map(edge => {
          const from = positions.get(edge.from)
          const to = positions.get(edge.to)
          if (!from || !to) return null
          const x1 = from.x + 150
          const y1 = from.y + 28
          const x2 = to.x
          const y2 = to.y + 28
          const mid = (x1 + x2) / 2
          return (
            <path key={`${edge.from}-${edge.to}`} d={`M ${x1} ${y1} C ${mid} ${y1}, ${mid} ${y2}, ${x2} ${y2}`}
              fill="none" stroke="var(--secondary)" strokeOpacity={0.45}
              strokeWidth={1 + 3 * edge.count / maxEdge} markerEnd="url(#mg-arrow)" />
          )
        })}
        {order.map(name => {
          const point = positions.get(name)!
          const info = activity(name)
          const selectedNode = selected === name
          return (
            <g key={name} className="mining-node" role="button" tabIndex={0}
              onClick={() => onSelect(name)}
              onKeyDown={event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(name) } }}>
              <rect x={point.x} y={point.y} width={156} height={64} rx={8}
                fill="var(--accent)" fillOpacity={selectedNode ? 0.22 : 0.10}
                stroke={selectedNode ? 'var(--accent)' : 'var(--border-strong)'} strokeWidth={selectedNode ? 2 : 1} />
              <text x={point.x + 9} y={point.y + 18} className="mining-node-title">{name.length > 23 ? `${name.slice(0, 22)}…` : name}</text>
              <text x={point.x + 9} y={point.y + 37} className="mining-node-sub">{info?.events ?? 0} events · {Math.round(info?.wait ?? 0)} min wait</text>
              <text x={point.x + 9} y={point.y + 53} className="mining-node-sub">{info?.resources.slice(0, 2).join(' · ') || '—'}</text>
            </g>
          )
        })}
      </svg>
    </div>
  )
}
