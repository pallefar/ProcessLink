import { useState } from 'react'
import { useApp } from '../App'
import { FeedbackPanel, type FeedbackSubject } from './FeedbackPanel'

export function FeedbackButton({ subject }: { subject: FeedbackSubject }) {
  const { feedback } = useApp()
  const [open, setOpen] = useState(false)
  const count = feedback.filter(item => item.kind === subject.kind && item.subjectId === subject.subjectId && !item.parentId && !item.resolved).length
  return (
    <>
      <button className="btn small" onClick={() => setOpen(true)}>
        Feedback{count ? ` ${count}` : ''}
      </button>
      {open && (
        <div className="modal-backdrop" onClick={() => setOpen(false)}>
          <div className="modal-card" onClick={event => event.stopPropagation()}>
            <FeedbackPanel subject={subject} onClose={() => setOpen(false)} />
          </div>
        </div>
      )}
    </>
  )
}
