import { useEffect, useState } from 'react'
import { useApp } from '../App'
import { loadOsState, saveOsState } from '../domain/osState'

interface PageNote {
  id: string
  page: string
  body: string
  author: string
  createdAt: string
}

const KEY = 'notes.v1'

function local(): PageNote[] {
  try { return JSON.parse(localStorage.getItem('processlink.notes.v1') || '[]') as PageNote[] } catch { return [] }
}

export function FloatingNotes() {
  const { page } = useApp()
  const [notes, setNotes] = useState<PageNote[]>(local)
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState('')

  useEffect(() => {
    void loadOsState<PageNote[]>(KEY).then(remote => { if (Array.isArray(remote)) setNotes(remote) })
  }, [])

  const persist = (next: PageNote[]) => {
    setNotes(next)
    try { localStorage.setItem('processlink.notes.v1', JSON.stringify(next)) } catch { /* ignore */ }
    void saveOsState(KEY, next)
  }
  const current = notes.filter(note => note.page === page)
  const count = current.length

  return (
    <div className="floating-notes">
      {open && (
        <div className="floating-notes-panel">
          <div className="floating-notes-head">
            <strong>Notes · {page}</strong>
            <button className="icon-btn" onClick={() => setOpen(false)} aria-label="Close notes">×</button>
          </div>
          <div className="floating-notes-list">
            {current.length === 0 && <p className="subtle">No notes on this page yet. They stay local.</p>}
            {current.map(note => (
              <div className="floating-note" key={note.id}>
                <p>{note.body}</p>
                <div className="row-meta"><span className="tiny">{note.author} · {new Date(note.createdAt).toLocaleString('en-GB')}</span><button className="btn small" onClick={() => persist(notes.filter(item => item.id !== note.id))}>Delete</button></div>
              </div>
            ))}
          </div>
          <textarea rows={3} placeholder="Write a local note for this page…" value={draft} onChange={event => setDraft(event.target.value)} />
          <div className="row-meta">
            <span className="tiny">Local · OS-backed when mounted</span>
            <button className="btn small primary" disabled={!draft.trim()} onClick={() => {
              const note: PageNote = { id: crypto.randomUUID(), page, body: draft.trim(), author: 'CI Manager (role)', createdAt: new Date().toISOString() }
              persist([...notes, note]); setDraft('')
            }}>Save note</button>
          </div>
        </div>
      )}
      <button className="floating-notes-button" onClick={() => setOpen(value => !value)} aria-label="Page notes">
        <span aria-hidden="true">✎</span>
        {count > 0 && <span className="floating-notes-count">{count}</span>}
      </button>
    </div>
  )
}
