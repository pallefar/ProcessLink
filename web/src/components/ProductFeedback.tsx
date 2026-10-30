import { useState } from 'react'

interface ProductFeedback {
  rating: 'ok' | 'minor' | 'major'
  priority: 'low' | 'normal' | 'high'
  category: string
  comment: string
  author: string
  page: string
  createdAt: string
}

const KEY = 'processlink.productfeedback.v1'

function save(record: ProductFeedback) {
  try {
    const existing = JSON.parse(localStorage.getItem(KEY) || '[]') as ProductFeedback[]
    localStorage.setItem(KEY, JSON.stringify([record, ...existing].slice(0, 100)))
  } catch { /* ignore */ }
}

export function ProductFeedbackButton({ page }: { page: string }) {
  const [open, setOpen] = useState(false)
  const [rating, setRating] = useState<ProductFeedback['rating']>('ok')
  const [priority, setPriority] = useState<ProductFeedback['priority']>('normal')
  const [category, setCategory] = useState('')
  const [comment, setComment] = useState('')
  const [author, setAuthor] = useState('CI Manager (role)')
  const [sent, setSent] = useState(false)

  const close = () => { setOpen(false); setSent(false); setComment(''); setCategory('') }

  return (
    <>
      <button className="btn small" onClick={() => setOpen(true)}>Send feedback</button>
      {open && (
        <div className="modal-backdrop" onClick={close}>
          <div className="modal-card" onClick={event => event.stopPropagation()} style={{ maxWidth: 520 }}>
            <h3 style={{ marginTop: 0 }}>Send feedback</h3>
            {sent ? (
              <div className="stack">
                <p>Feedback saved locally. It is not sent to a model or a server.</p>
                <button className="btn primary" onClick={close}>Done</button>
              </div>
            ) : (
              <div className="stack">
                <div className="segmented">
                  {(['low', 'normal', 'high'] as const).map(value => (
                    <button key={value} aria-selected={priority === value} onClick={() => setPriority(value)}>
                      {value === 'low' ? 'Low' : value === 'normal' ? 'Normal' : 'High'}
                    </button>
                  ))}
                </div>
                <div className="segmented">
                  {(['ok', 'minor', 'major'] as const).map(value => (
                    <button key={value} aria-selected={rating === value} onClick={() => setRating(value)}>
                      {value === 'ok' ? 'OK' : value === 'minor' ? 'Minor issue' : 'Major issue'}
                    </button>
                  ))}
                </div>
                <input placeholder="Category (optional)" value={category} onChange={e => setCategory(e.target.value)} />
                <input placeholder="Name / role" value={author} onChange={e => setAuthor(e.target.value)} />
                <textarea rows={4} placeholder="What should we improve?" value={comment} onChange={e => setComment(e.target.value)} />
                <p className="subtle">Saved locally; never sent to a model or the network.</p>
                <div className="row-meta">
                  <button className="btn" onClick={close}>Cancel</button>
                  <button className="btn primary" disabled={!comment.trim()} onClick={() => {
                    save({ rating, priority, category, comment: comment.trim(), author: author.trim() || 'CI Manager (role)', page, createdAt: new Date().toISOString() })
                    setSent(true)
                  }}>Save feedback</button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </>
  )
}
