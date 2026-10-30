import { useEffect, useState } from 'react'
import { Card, Chip } from './ui'

interface Activity { text: string; at: string }

export function OsActivity() {
  const [items, setItems] = useState<Activity[]>([])
  const [status, setStatus] = useState<'connecting' | 'live' | 'closed'>('connecting')

  useEffect(() => {
    let source: EventSource | null = null
    try {
      source = new EventSource('/api/events')
      source.onopen = () => setStatus('live')
      source.onerror = () => setStatus('closed')
      source.onmessage = event => {
        try {
          const data = JSON.parse(event.data) as { type?: string; event?: string; actor?: string; at?: string; ts?: string }
          const text = `${data.type ?? data.event ?? 'OS event'}${data.actor ? ` · ${data.actor}` : ''}`
          setItems(current => [{ text, at: data.at ?? data.ts ?? new Date().toISOString() }, ...current].slice(0, 6))
        } catch {
          setItems(current => [{ text: event.data.slice(0, 120), at: new Date().toISOString() }, ...current].slice(0, 6))
        }
      }
    } catch {
      setStatus('closed')
    }
    return () => source?.close()
  }, [])

  return (
    <Card title="OS activity" subtitle="Server-sent OS events through the same session." glyph="⌁">
      <div className="row-meta">
        <Chip tone={status === 'live' ? 'green' : status === 'connecting' ? 'orange' : undefined}>
          {status === 'live' ? 'Live' : status === 'connecting' ? 'Connecting' : 'Unavailable'}
        </Chip>
        <span className="tiny">Read-only event stream</span>
      </div>
      {items.length === 0 ? <p className="subtle">Waiting for the next OS event.</p> : items.map((item, index) => (
        <div className="os-activity-row" key={`${item.at}-${index}`}>
          <span>{item.text}</span><span className="tiny">{new Date(item.at).toLocaleTimeString('en-GB')}</span>
        </div>
      ))}
    </Card>
  )
}
