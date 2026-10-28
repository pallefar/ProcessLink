import type { Process, Step } from '../domain/types'
import { fmt } from '../domain/rules'

export type Overlay = 'cycle' | 'handoffs' | 'rework' | 'automation'

const automationFit = (step: Step): number => {
  switch (step.waste) {
    case 'unusedTalent': return 0.9
    case 'overProcessing': return 0.8
    case 'rework': return 0.65
    case 'handoffs': return 0.6
    case 'contextSwitching': return 0.5
    case 'defects': return 0.45
    case 'waiting': return 0.35
    case 'backlog': return 0.25
  }
}

export function overlayValue(step: Step, steps: Step[], overlay: Overlay): number {
  switch (overlay) {
    case 'cycle': return step.minutes / Math.max(1, ...steps.map(s => s.minutes))
    case 'handoffs': return step.handoffs / Math.max(1, ...steps.map(s => s.handoffs))
    case 'rework': return step.rework / Math.max(0.01, ...steps.map(s => s.rework))
    case 'automation': return automationFit(step)
  }
}

export function overlayText(step: Step, overlay: Overlay): string {
  switch (overlay) {
    case 'cycle': return fmt.minutes(step.minutes)
    case 'handoffs': return `${step.handoffs} handoff${step.handoffs === 1 ? '' : 's'}`
    case 'rework': return `${fmt.percent(step.rework)} rework`
    case 'automation': return `${fmt.percent(automationFit(step))} fit`
  }
}

const wrap = (text: string, max = 19): string[] => {
  if (text.length <= max) return [text]
  const words = text.split(' ')
  const lines: string[] = []
  let line = ''
  for (const word of words) {
    if ((line + ' ' + word).trim().length > max && line) {
      lines.push(line)
      line = word
    } else {
      line = (line + ' ' + word).trim()
    }
  }
  if (line) lines.push(line)
  return lines.slice(0, 2).map((value, index, all) =>
    index === all.length - 1 && text.length > max * 2 ? value.slice(0, max - 1) + '…' : value)
}

export function MapSvg({ process, overlay, selected, onSelect }: {
  process: Process
  overlay: Overlay
  selected?: string
  onSelect: (step: Step) => void
}) {
  const lanes = [...new Set(process.steps.map(step => step.role))]
  const laneHeight = 112
  const labelWidth = 120
  const column = 170
  const nodeWidth = 154
  const width = Math.max(720, labelWidth + 20 + process.steps.length * column)
  const height = Math.max(160, lanes.length * laneHeight + 16)

  return (
    <div className="map-wrap">
      <svg className="map-svg" viewBox={`0 0 ${width} ${height}`} width={width} height={height} role="img"
        aria-label={`Swimlane map of ${process.name}, ${process.steps.length} steps, overlay ${overlay}`}>
        <defs>
          <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
            <path d="M 0 0 L 10 5 L 0 10 z" fill="var(--secondary)" />
          </marker>
        </defs>
        {lanes.map((lane, index) => (
          <g key={lane}>
            <rect x={0} y={index * laneHeight + 8} width={width} height={laneHeight - 8} rx={10}
              fill={index % 2 === 0 ? 'rgba(127,127,127,0.06)' : 'transparent'} />
            <text x={12} y={index * laneHeight + laneHeight / 2 + 4} fill="var(--secondary)" fontSize={10.5} fontWeight={500}>{lane}</text>
          </g>
        ))}

        {process.steps.map((step, index) => {
          const previous = process.steps[index - 1]
          if (!previous) return null
          const fromLane = lanes.indexOf(previous.role)
          const toLane = lanes.indexOf(step.role)
          const x1 = labelWidth + 20 + (index - 1) * column + nodeWidth
          const y1 = fromLane * laneHeight + laneHeight / 2 + 4
          const x2 = labelWidth + 20 + index * column
          const y2 = toLane * laneHeight + laneHeight / 2 + 4
          const mid = (x1 + x2) / 2
          return (
            <path key={`e-${step.id}`} d={`M ${x1} ${y1} C ${mid} ${y1}, ${mid} ${y2}, ${x2} ${y2}`}
              fill="none" stroke="var(--secondary)" strokeOpacity={0.45} strokeWidth={1.4} markerEnd="url(#arrow)" />
          )
        })}

        {process.steps.map((step, index) => {
          const lane = Math.max(0, lanes.indexOf(step.role))
          const x = labelWidth + 20 + index * column
          const y = lane * laneHeight + (laneHeight - 8) / 2 - 30
          const t = Math.min(1, Math.max(0, overlayValue(step, process.steps, overlay)))
          const hue = 140 - 135 * t
          const lines = wrap(step.name)
          return (
            <g key={step.id} className="map-node" data-selected={selected === step.id} role="button" tabIndex={0}
              aria-label={`${step.name}, ${step.role}, ${overlayText(step, overlay)}`}
              onClick={() => onSelect(step)}
              onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(step) } }}>
              <rect className="box" x={x} y={y} width={nodeWidth} height={62} rx={8} style={{ fill: `hsla(${hue}, 55%, 45%, 0.18)` }} />
              {lines.map((line, lineIndex) => (
                <text key={line} x={x + 9} y={y + 17 + lineIndex * 12} fontWeight={600}>{line}</text>
              ))}
              <text className="sub" x={x + 9} y={y + 46}>{step.application}</text>
              <text className="sub" x={x + 9} y={y + 58} style={{ fontVariantNumeric: 'tabular-nums' }}>{overlayText(step, overlay)}</text>
              <text className="sub" x={x + nodeWidth - 9} y={y + 58} textAnchor="end">{step.waste === 'handoffs' ? '⇄' : ''}</text>
            </g>
          )
        })}
      </svg>
    </div>
  )
}
