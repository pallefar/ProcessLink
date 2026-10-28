import type { ReactNode } from 'react'
import type { Route, SavingsStage } from '../domain/types'

export type Tone = 'green' | 'orange' | 'red' | 'blue' | 'purple' | 'teal' | undefined

export function Chip({ children, tone, solid = false }: { children: ReactNode; tone?: Tone; solid?: boolean }) {
  return <span className="chip" data-tone={tone} data-solid={solid || undefined}>{children}</span>
}

export function Card({ title, subtitle, glyph, actions, children }: {
  title?: string; subtitle?: string; glyph?: string; actions?: ReactNode; children: ReactNode
}) {
  return (
    <section className="card">
      {(title || actions) && (
        <header className="card-head">
          <div>
            <h2>{glyph && <span className="glyph" aria-hidden="true">{glyph} </span>}{title}</h2>
            {subtitle && <p>{subtitle}</p>}
          </div>
          {actions && <div style={{ marginLeft: 'auto' }}>{actions}</div>}
        </header>
      )}
      {children}
    </section>
  )
}

export function PageHead({ title, subtitle, actions }: { title: string; subtitle: string; actions?: ReactNode }) {
  return (
    <header className="page-head">
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      {actions && <div className="actions">{actions}</div>}
    </header>
  )
}

export function Metric({ label, value, detail, glyph }: { label: string; value: string; detail: string; glyph?: string }) {
  return (
    <div className="metric">
      <div className="label"><span aria-hidden="true">{glyph}</span>{label}</div>
      <div className="value">{value}</div>
      <div className="detail">{detail}</div>
    </div>
  )
}

export function Meter({ label, value, valueText, tone }: {
  label: string; value: number; valueText?: string; tone?: 'green' | 'orange' | 'red' | 'purple' | 'teal'
}) {
  const width = Math.min(100, Math.max(0, value))
  return (
    <div className="meter">
      <div className="meter-label"><span>{label}</span><span>{valueText ?? Math.round(value)}</span></div>
      <div className="track" role="progressbar" aria-label={label} aria-valuenow={Math.round(value)} aria-valuemin={0} aria-valuemax={100}>
        <div className={`fill ${tone ?? ''}`} style={{ width: `${width}%` }} />
      </div>
    </div>
  )
}

export function KV({ items }: { items: Array<[string, ReactNode]> }) {
  return (
    <dl className="kv">
      {items.map(([key, value]) => (
        <div key={key} style={{ display: 'contents' }}>
          <dt>{key}</dt>
          <dd>{value}</dd>
        </div>
      ))}
    </dl>
  )
}

export function Note({ children, glyph = '⛨' }: { children: ReactNode; glyph?: string }) {
  return <div className="note"><span className="glyph" aria-hidden="true">{glyph}</span><span>{children}</span></div>
}

export function Empty({ title, detail }: { title: string; detail: string }) {
  return <div className="empty"><strong>{title}</strong><span>{detail}</span></div>
}

export const routeTone = (route: Route): Tone =>
  route === 'eliminate' ? 'red'
    : route === 'simplify' ? 'orange'
      : route === 'standardize' ? 'blue'
        : route === 'automate' ? 'purple' : undefined

export const stageTone = (stage: SavingsStage): Tone =>
  stage === 'validated' ? 'green' : stage === 'committed' ? 'blue' : 'orange'

export const statusTone = (status: string): Tone =>
  status === 'done' ? 'green'
    : status === 'inProgress' ? 'blue'
      : status === 'blocked' ? 'red' : undefined
