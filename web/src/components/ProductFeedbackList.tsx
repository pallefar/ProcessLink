import { useEffect, useState } from 'react'
import { Card, Chip } from './ui'

interface ProductFeedback {
  rating: 'ok' | 'minor' | 'major'
  priority: 'low' | 'normal' | 'high'
  category: string
  comment: string
  author: string
  page: string
  createdAt: string
}

export function ProductFeedbackList() {
  const [items, setItems] = useState<ProductFeedback[]>([])
  const [priority, setPriority] = useState<'all' | 'low' | 'normal' | 'high'>('all')

  useEffect(() => {
    try {
      const stored = JSON.parse(localStorage.getItem('processlink.productfeedback.v1') || '[]') as ProductFeedback[]
      setItems(stored)
    } catch { /* ignore */ }
  }, [])

  const visible = items.filter(item => priority === 'all' || item.priority === priority)

  return (
    <Card title="Product feedback" subtitle="Saved on this Mac; not sent anywhere." glyph="☆">
      <div className="row-meta" style={{ marginBottom: 6 }}>
        {(['all', 'high', 'normal', 'low'] as const).map(value => (
          <button key={value} className="btn small" aria-pressed={priority === value} onClick={() => setPriority(value)}>{value.charAt(0).toUpperCase() + value.slice(1)}</button>
        ))}
        <Chip>{items.length} total</Chip>
      </div>
      {visible.length === 0 ? <p className="subtle">No product feedback yet.</p> : visible.slice(0, 12).map((item, index) => (
        <div className="feedback-card" key={`${item.createdAt}-${index}`} style={{ marginBottom: 6 }}>
          <div className="feedback-meta"><strong>{item.author}</strong><span>{new Date(item.createdAt).toLocaleString('en-GB')}</span></div>
          <div className="row-meta" style={{ marginTop: 4 }}>
            <Chip tone={item.priority === 'high' ? 'red' : item.priority === 'low' ? undefined : 'blue'}>{item.priority}</Chip>
            <Chip tone={item.rating === 'ok' ? 'green' : item.rating === 'minor' ? 'orange' : 'red'}>{item.rating}</Chip>
            {item.category && <Chip>{item.category}</Chip>}
          </div>
          <p>{item.comment}</p>
        </div>
      ))}
    </Card>
  )
}
