import { useState } from 'react'
import { useApp } from '../App'
import { Card, Chip, Empty } from '../components/ui'
import { FeedbackPanel, type FeedbackSubject } from '../components/FeedbackPanel'
import type { FeedbackKind } from '../domain/types'
import { ProductFeedbackButton } from '../components/ProductFeedback'

const KIND_LABEL: Record<FeedbackKind, string> = {
  map: 'Map', mapShape: 'Map shape', process: 'Process', opportunity: 'Opportunity',
  initiative: 'Initiative', meeting: 'Meeting', miningCase: 'Mining case',
}

export default function Feedback() {
  const { feedback } = useApp()
  const [filter, setFilter] = useState<'open' | 'resolved' | 'all'>('open')
  const [selected, setSelected] = useState<FeedbackSubject>()

  const roots = feedback.filter(item => {
    if (item.parentId) return false
    if (filter === 'open') return !item.resolved
    if (filter === 'resolved') return item.resolved
    return true
  }).sort((a, b) => b.createdAt.localeCompare(a.createdAt))
  const openCount = feedback.filter(i => !i.parentId && !i.resolved).length
  const resolvedCount = feedback.filter(i => !i.parentId && i.resolved).length
  const active = selected ?? (roots[0] ? { kind: roots[0].kind, subjectId: roots[0].subjectId, subjectLabel: roots[0].subjectLabel } : undefined)
  const exportCSV = () => {
    const rows = [['type', 'kind', 'subject', 'rating', 'priority', 'resolved', 'author', 'createdAt', 'body']]
    for (const item of feedback) rows.push(['annotation', item.kind, item.subjectLabel, '', '', item.resolved ? 'yes' : 'no', item.author, item.createdAt, item.body])
    try {
      const product = JSON.parse(localStorage.getItem('processlink.productfeedback.v1') || '[]') as Array<{ rating: string; priority: string; comment: string; author: string; createdAt: string }>
      for (const item of product) rows.push(['product', '', '', item.rating, item.priority, '', item.author, item.createdAt, item.comment])
    } catch { /* ignore */ }
    const csv = rows.map(row => row.map(value => `"${String(value).replaceAll('"', '""')}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' }); const url = URL.createObjectURL(blob)
    const link = document.createElement('a'); link.href = url; link.download = 'processlink-feedback.csv'; link.click(); URL.revokeObjectURL(url)
  }
  const exportForPdfStudio = () => {
    const threads = feedback.filter(item => !item.parentId).map(root => ({
      subject: { kind: root.kind, id: root.subjectId, label: root.subjectLabel },
      comment: { author: root.author, createdAt: root.createdAt, body: root.body, resolved: root.resolved, mentions: root.mentions },
      replies: feedback.filter(item => item.parentId === root.id).map(reply => ({ author: reply.author, createdAt: reply.createdAt, body: reply.body })),
    }))
    const blob = new Blob([JSON.stringify({ schema: 'processlink-annotations/1', generatedAt: new Date().toISOString(), threads }, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob); const link = document.createElement('a')
    link.href = url; link.download = 'processlink-annotations.json'; link.click(); URL.revokeObjectURL(url)
  }

  return (
    <div className="feedback-page">
      <div className="page-head">
        <div>
          <h2 className="page-title">Feedback</h2>
          <p className="page-sub">Annotations and questions on maps, shapes, processes, opportunities and initiatives. Comments stay local.</p>
        </div>
        <div className="row-meta">
          <Chip tone="orange">{openCount} open</Chip>
          <Chip tone="green">{resolvedCount} resolved</Chip>
          <button className="btn small" onClick={exportForPdfStudio}>Export for PDF Studio</button>
          <button className="btn small" onClick={exportCSV}>Export CSV</button>
          <ProductFeedbackButton page="feedback" />
        </div>
      </div>

      <div className="segmented" role="tablist" aria-label="Feedback filter">
        {(['open', 'resolved', 'all'] as const).map(item => (
          <button key={item} role="tab" aria-selected={filter === item} onClick={() => setFilter(item)}>{item.charAt(0).toUpperCase() + item.slice(1)}</button>
        ))}
      </div>

      <div className="feedback-layout">
        <Card title="Threads" subtitle={`${roots.length} conversations`} glyph="◌">
          {roots.length === 0 ? <Empty title="No feedback in this view" detail="Add feedback from a map or map shape." /> : (
            <div className="feedback-inbox">
              {roots.map(root => {
                const replies = feedback.filter(item => item.parentId === root.id).length
                return (
                  <button key={root.id} className="feedback-row" onClick={() => setSelected({ kind: root.kind, subjectId: root.subjectId, subjectLabel: root.subjectLabel })}>
                    <span className="feedback-kind">{KIND_LABEL[root.kind]}</span>
                    <div>
                      <strong>{root.subjectLabel}</strong>
                      <p>{root.body}</p>
                      <span className="subtle">{root.author} · {new Date(root.createdAt).toLocaleDateString('en-GB')} · {replies} replies</span>
                    </div>
                    <Chip tone={root.resolved ? 'green' : 'orange'}>{root.resolved ? 'Resolved' : 'Open'}</Chip>
                  </button>
                )
              })}
            </div>
          )}
        </Card>
        <Card title={active ? 'Thread' : 'Select a thread'} subtitle={active?.subjectLabel ?? 'Pick a conversation to reply or resolve.'} glyph="↩">
          {active ? <FeedbackPanel subject={active} /> : <p className="subtle">Select a conversation from the list.</p>}
        </Card>
      </div>
    </div>
  )
}
