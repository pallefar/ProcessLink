import { useMemo, useState } from 'react'
import { Card, Chip, Metric, Note } from '../components/ui'

interface Policy {
  active: boolean
  intervalMinutes: number
  maxSessionMinutes: number
  windowTitles: boolean
  screenshots: boolean
  inputCounts: boolean
  consentVersion: string
  consentReference: string
}

const KEY = 'processlink.agent.policy.v1'

function load(): Policy {
  try {
    const raw = localStorage.getItem(KEY)
    if (raw) return JSON.parse(raw) as Policy
  } catch { /* ignore */ }
  return { active: false, intervalMinutes: 60, maxSessionMinutes: 15, windowTitles: false, screenshots: false, inputCounts: false, consentVersion: 'v1', consentReference: '' }
}

export default function Agent() {
  const [policy, setPolicy] = useState<Policy>(load)
  const update = (patch: Partial<Policy>) => setPolicy(current => {
    const next = { ...current, ...patch }
    localStorage.setItem(KEY, JSON.stringify(next))
    return next
  })
  const download = () => {
    const blob = new Blob([JSON.stringify({ schema: 'processlink-agent-policy/1', policy }, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url; link.download = 'processlink-agent-policy.json'; link.click(); URL.revokeObjectURL(url)
  }
  const content = useMemo(() => policy.windowTitles || policy.screenshots || policy.inputCounts, [policy])

  return (
    <div className="agent-page">
      <div className="page-head">
        <div>
          <h2 className="page-title">Capture agent</h2>
          <p className="page-sub">Policy and consent are managed here; the actual desktop sampler runs in the macOS app.</p>
        </div>
        <div className="row-meta">
          <Chip tone={policy.active ? 'green' : undefined}>{policy.active ? 'Policy active' : 'Policy off'}</Chip>
          <Chip tone={content ? 'orange' : 'green'}>{content ? 'Content opt-in' : 'App usage only'}</Chip>
        </div>
      </div>

      <div className="grid metrics">
        <Metric label="Interval" value={`${policy.intervalMinutes} min`} detail="Between sessions" />
        <Metric label="Max session" value={`${policy.maxSessionMinutes} min`} detail="Auto-stops and saves" />
        <Metric label="Consent" value={policy.consentReference ? 'Recorded' : 'Needed'} detail={`Version ${policy.consentVersion}`} />
      </div>

      <div className="grid two wide">
        <Card title="Policy" subtitle="A local policy, not a fleet server." glyph="◉">
          <label className="check-row"><input type="checkbox" checked={policy.active} onChange={e => update({ active: e.target.checked })} /> Agent policy active</label>
          <div className="sim-row"><span>Interval</span><input type="number" min={15} max={1440} step={15} value={policy.intervalMinutes} onChange={e => update({ intervalMinutes: Number(e.target.value) })} /><span>min</span></div>
          <div className="sim-row"><span>Max session</span><input type="number" min={1} max={120} value={policy.maxSessionMinutes} onChange={e => update({ maxSessionMinutes: Number(e.target.value) })} /><span>min</span></div>
          <div className="divider" />
          <label className="check-row"><input type="checkbox" checked={policy.windowTitles} onChange={e => update({ windowTitles: e.target.checked })} /> Window titles</label>
          <label className="check-row"><input type="checkbox" checked={policy.screenshots} onChange={e => update({ screenshots: e.target.checked })} /> Local screenshots</label>
          <label className="check-row"><input type="checkbox" checked={policy.inputCounts} onChange={e => update({ inputCounts: e.target.checked })} /> Keystroke/click counts</label>
        </Card>
        <Card title="Consent" subtitle="Per site/role/version, never per named person." glyph="✓">
          <div className="sim-row"><span>Version</span><input value={policy.consentVersion} onChange={e => update({ consentVersion: e.target.value })} /><span /></div>
          <div className="sim-row"><span>Reference</span><input placeholder="Agreement id" value={policy.consentReference} onChange={e => update({ consentReference: e.target.value })} /><span /></div>
          <Note>Browser builds cannot record desktop consent or start a sampler. Export the policy and apply it in the macOS app.</Note>
          <button className="btn primary" onClick={download}>Export policy JSON</button>
        </Card>
      </div>
    </div>
  )
}
