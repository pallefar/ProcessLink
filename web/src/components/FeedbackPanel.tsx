import { useState } from 'react'
import { useApp } from '../App'
import { Chip } from './ui'
import type { FeedbackKind } from '../domain/types'

export interface FeedbackSubject {
  kind: FeedbackKind
  subjectId: string
  subjectLabel: string
}

export function FeedbackPanel({ subject, onClose }: { subject: FeedbackSubject; onClose?: () => void }) {
  const { feedback, addFeedback, setFeedbackResolved } = useApp()
  const [draft, setDraft] = useState('')
  const [replyTo, setReplyTo] = useState<string>()
  const [replyDraft, setReplyDraft] = useState('')

  const records = feedback.filter(item => item.kind === subject.kind && item.subjectId === subject.subjectId)
  const roots = records.filter(item => !item.parentId).sort((a, b) => b.createdAt.localeCompare(a.createdAt))
  const open = roots.filter(item => !item.resolved).length

  return (
    <div className="feedback-panel">
      <div className="feedback-head">
        <div>
          <strong>Feedback · {subject.kind}</strong>
          <p>{subject.subjectLabel}</p>
        </div>
        <div className="row-meta">
          <Chip tone={open ? 'orange' : 'green'}>{open} open</Chip>
          {onClose && <button className="btn small" onClick={onClose}>Close</button>}
        </div>
      </div>

      <div className="feedback-list">
        {roots.length === 0 && <p className="subtle">No feedback yet. Leave a comment or @mention a role.</p>}
        {roots.map(root => {
          const replies = records.filter(item => item.parentId === root.id).sort((a, b) => a.createdAt.localeCompare(b.createdAt))
          return (
            <article key={root.id} className={`feedback-card ${root.resolved ? 'is-resolved' : ''}`}>
              <div className="feedback-meta"><strong>{root.author}</strong><span>{new Date(root.createdAt).toLocaleString('en-GB')}</span></div>
              {root.page ? <Chip tone="blue">Page {root.page}</Chip> : null}
              <p>{root.body}</p>
              <div className="row-meta">{root.mentions.map(m => <Chip key={m} tone="blue">{m}</Chip>)}</div>
              {replies.map(reply => (
                <div className="feedback-reply" key={reply.id}>
                  <div className="feedback-meta"><strong>{reply.author}</strong><span>{new Date(reply.createdAt).toLocaleString('en-GB')}</span></div>
                  <p>{reply.body}</p>
                </div>
              ))}
              <div className="feedback-actions">
                <button className="btn small" onClick={() => setFeedbackResolved(root.id, !root.resolved)}>
                  {root.resolved ? 'Reopen' : 'Resolve'}
                </button>
                <button className="btn small" onClick={() => setReplyTo(replyTo === root.id ? undefined : root.id)}>Reply</button>
                {root.resolved && <Chip tone="green">Resolved</Chip>}
              </div>
              {replyTo === root.id && (
                <div className="feedback-compose">
                  <textarea value={replyDraft} onChange={e => setReplyDraft(e.target.value)} placeholder="Reply…" rows={2} />
                  <button className="btn small primary" disabled={!replyDraft.trim()} onClick={() => {
                    if (!addFeedback({ ...subject, body: replyDraft, parentId: root.id })) return
                    setReplyDraft(''); setReplyTo(undefined)
                  }}>Send reply</button>
                </div>
              )}
            </article>
          )
        })}
      </div>

      <div className="feedback-compose">
        <textarea value={draft} onChange={e => setDraft(e.target.value)} placeholder="Comment or @mention a role…" rows={2} />
        <div className="feedback-compose-row">
          <button className="btn small" onClick={() => setDraft(v => `${v}${v ? ' ' : ''}@`)}>@ Mention</button>
          <span className="subtle">Local annotation only</span>
          <button className="btn small primary" disabled={!draft.trim()} onClick={() => {
            if (!addFeedback({ ...subject, body: draft })) return
            setDraft('')
          }}>Comment</button>
        </div>
      </div>
    </div>
  )
}
