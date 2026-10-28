import { useState } from 'react'
import { useApp } from '../App'
import { Card, Chip, Empty, KV, Note, PageHead } from '../components/ui'
import { BLOCK_LABEL, MEETING_LABEL } from '../domain/labels'
import type { BlockKind, MeetingKind } from '../domain/types'

const BLOCK_KINDS: BlockKind[] = ['heading', 'text', 'bullet', 'checklist', 'decision', 'action', 'callout', 'link']
const MEETING_KINDS: MeetingKind[] = ['dailyHuddle', 'kaizen', 'a3Review', 'leadership', 'workshop', 'oneToOne']

export default function Meetings() {
  const { meetings, blocks, selectedMeeting, selectMeeting, createMeeting } = useApp()
  const [search, setSearch] = useState('')
  const filtered = meetings.filter(meeting =>
    !search.trim() || meeting.title.toLowerCase().includes(search.toLowerCase())
    || meeting.summary.toLowerCase().includes(search.toLowerCase())
    || blocks.some(b => b.meetingId === meeting.id && b.text.toLowerCase().includes(search.toLowerCase())))
  const meeting = filtered.find(m => m.id === selectedMeeting) ?? filtered[0]
  const openActions = meeting ? blocks.filter(b => b.meetingId === meeting.id && b.kind === 'action' && !b.checked).length : 0

  return (
    <>
      <PageHead title="Meetings" subtitle="Notion-style pages for the work: typed blocks, decisions and actions linked to the process, the initiative and the graph."
        actions={<select
          aria-label="New meeting page"
          value=""
          onChange={event => { if (event.target.value) createMeeting(event.target.value as MeetingKind) }}
          style={{ border: '1px solid var(--border-strong)', background: 'var(--panel)', borderRadius: 8, padding: '4px 8px', fontSize: 12 }}
        >
          <option value="">New page…</option>
          {MEETING_KINDS.map(kind => <option key={kind} value={kind}>{MEETING_LABEL[kind]}</option>)}
        </select>}
      />

      {!meeting ? <Empty title="No meeting pages" detail="Start a daily huddle, kaizen or A3 review from New page." /> : (
        <div className="split">
          <div className="list-pane">
            <div className="pane-head"><strong>{filtered.length} pages</strong><span className="tiny" style={{ marginLeft: 'auto' }}>{openActions} open</span></div>
            <div style={{ padding: '0 12px 8px' }}>
              <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search pages and notes"
                aria-label="Search meeting pages"
                style={{ width: '100%', border: '1px solid var(--border)', background: 'var(--panel)', borderRadius: 6, padding: '5px 8px', fontSize: 11.5 }} />
            </div>
            <div className="scroll-list" role="listbox" aria-label="Meeting pages">
              {filtered.map(item => {
                const itemOpen = blocks.filter(b => b.meetingId === item.id && b.kind === 'action' && !b.checked).length
                return (
                  <button key={item.id} className="row" role="option" aria-selected={item.id === meeting.id}
                    onClick={() => selectMeeting(item.id)} style={{ alignItems: 'flex-start' }}>
                    <span aria-hidden="true" style={{ marginTop: 2, color: 'var(--secondary)' }}>◫</span>
                    <span style={{ minWidth: 0 }}>
                      <div className="title">{item.title}</div>
                      <div className="sub">
                        {new Date(item.date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}
                        {' · '}{item.durationMinutes} min{item.site ? ` · ${item.site}` : ''}
                      </div>
                      <div className="rowflex" style={{ marginTop: 4 }}>
                        <Chip>{MEETING_LABEL[item.kind]}</Chip>
                        {itemOpen > 0 && <Chip tone="orange">{itemOpen} open</Chip>}
                      </div>
                    </span>
                    <span className="right">
                      <Chip tone={item.status === 'done' ? 'green' : item.status === 'notes' ? 'blue' : undefined}>{item.status === 'done' ? 'Done' : item.status === 'notes' ? 'Notes' : 'Planned'}</Chip>
                    </span>
                  </button>
                )
              })}
            </div>
          </div>
          <div className="detail-pane"><MeetingDetail id={meeting.id} /></div>
        </div>
      )}
    </>
  )
}

function MeetingDetail({ id }: { id: string }) {
  const {
    meetings, blocks, processes, initiatives, selectedNode,
    updateMeeting, addMeetingBlock, updateBlock, deleteBlock, toggleBlock, linkMeeting,
    promoteAction, selectNode, navigate,
  } = useApp()
  const meeting = meetings.find(m => m.id === id)
  if (!meeting) return <Empty title="Not found" detail="This page was removed." />
  const items = blocks.filter(b => b.meetingId === id).sort((a, b) => a.order - b.order)
  const process = processes.find(p => p.id === meeting.processId)
  const initiative = initiatives.find(i => i.id === meeting.initiativeId)
  const open = items.filter(b => b.kind === 'action' && !b.checked)
  const decisions = items.filter(b => b.kind === 'decision' && b.text.trim())
  const dateValue = meeting.date.slice(0, 10)

  return (
    <div className="stack">
      <div>
        <input className="meeting-title" value={meeting.title} onChange={e => updateMeeting(id, { title: e.target.value })}
          aria-label="Meeting title" />
        <input className="meeting-summary" value={meeting.summary} placeholder="One-line summary"
          onChange={e => updateMeeting(id, { summary: e.target.value })} aria-label="Meeting summary" />
      </div>

      <div className="rowflex">
        <select value={meeting.kind} onChange={e => updateMeeting(id, { kind: e.target.value as MeetingKind })} aria-label="Meeting kind"
          style={{ border: '1px solid var(--border)', background: 'var(--panel-2)', borderRadius: 6, padding: '3px 6px', fontSize: 11 }}>
          {MEETING_KINDS.map(k => <option key={k} value={k}>{MEETING_LABEL[k]}</option>)}
        </select>
        <select value={meeting.status} onChange={e => updateMeeting(id, { status: e.target.value as typeof meeting.status })} aria-label="Meeting status"
          style={{ border: '1px solid var(--border)', background: 'var(--panel-2)', borderRadius: 6, padding: '3px 6px', fontSize: 11 }}>
          <option value="planned">Planned</option><option value="notes">Notes</option><option value="done">Done</option>
        </select>
        <input type="date" value={dateValue} onChange={e => updateMeeting(id, { date: new Date(e.target.value).toISOString() })} aria-label="Meeting date"
          style={{ border: '1px solid var(--border)', background: 'var(--panel-2)', borderRadius: 6, padding: '3px 6px', fontSize: 11 }} />
        <Chip tone="blue">{meeting.site || 'No site'}</Chip>
        <Chip>{meeting.owner}</Chip>
        <span className="tiny" style={{ marginLeft: 'auto' }}>{meeting.attendees.join(' · ')}</span>
      </div>

      <div className="rowflex">
        <label className="tiny">Process
          <select value={meeting.processId} onChange={e => linkMeeting(id, { processId: e.target.value })} aria-label="Linked process"
            style={{ marginLeft: 6, border: '1px solid var(--border)', background: 'var(--panel-2)', borderRadius: 6, padding: '3px 6px', fontSize: 11 }}>
            <option value="">Not linked</option>
            {processes.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </label>
        <label className="tiny">Initiative
          <select value={meeting.initiativeId} onChange={e => linkMeeting(id, { initiativeId: e.target.value })} aria-label="Linked initiative"
            style={{ marginLeft: 6, border: '1px solid var(--border)', background: 'var(--panel-2)', borderRadius: 6, padding: '3px 6px', fontSize: 11 }}>
            <option value="">Not linked</option>
            {initiatives.map(i => <option key={i.id} value={i.id}>{i.title}</option>)}
          </select>
        </label>
      </div>

      <Card title="Notes" subtitle="Blocks, not a text box. Decisions and actions become graph facts.">
        <div className="meeting-blocks">
          {items.map(item => (
            <div key={item.id} className="meeting-block" data-kind={item.kind}>
              <span className="meeting-block-kind" aria-hidden="true">{BLOCK_LABEL[item.kind].slice(0, 1)}</span>
              <div style={{ flex: 1, minWidth: 0 }}>
                {(item.kind === 'checklist' || item.kind === 'action') && (
                  <input type="checkbox" checked={item.checked} onChange={() => toggleBlock(item.id)}
                    aria-label="Mark done" style={{ marginRight: 6 }} />
                )}
                {item.kind === 'heading'
                  ? <input className="block-heading" value={item.text} onChange={e => updateBlock(item.id, { text: e.target.value })} aria-label="Heading" />
                  : <textarea className="block-text" rows={1} value={item.text}
                    onChange={e => updateBlock(item.id, { text: e.target.value })}
                    aria-label={BLOCK_LABEL[item.kind]} />}
                {item.kind === 'action' && (
                  <div className="rowflex" style={{ marginTop: 4 }}>
                    <input value={item.owner} onChange={e => updateBlock(item.id, { owner: e.target.value })}
                      placeholder="Owner role" aria-label="Action owner"
                      style={{ width: 150, border: '1px solid var(--border)', background: 'var(--panel)', borderRadius: 6, padding: '2px 6px', fontSize: 10.5 }} />
                    <input type="date" value={item.due?.slice(0, 10) ?? ''} onChange={e => updateBlock(item.id, { due: new Date(e.target.value).toISOString() })}
                      aria-label="Action due date"
                      style={{ border: '1px solid var(--border)', background: 'var(--panel)', borderRadius: 6, padding: '2px 6px', fontSize: 10.5 }} />
                    <button className="btn small" onClick={() => promoteAction(item.id)} disabled={!item.owner}>Promote</button>
                  </div>
                )}
              </div>
              <div className="rowflex" style={{ alignItems: 'flex-start' }}>
                <select aria-label="Block type" value={item.kind} onChange={e => updateBlock(item.id, { kind: e.target.value as BlockKind })}
                  style={{ border: '1px solid var(--border)', background: 'var(--panel-2)', borderRadius: 6, fontSize: 10, padding: '1px 3px' }}>
                  {BLOCK_KINDS.map(k => <option key={k} value={k}>{BLOCK_LABEL[k]}</option>)}
                </select>
                <button className="btn small" onClick={() => deleteBlock(item.id)} aria-label="Delete block">×</button>
              </div>
            </div>
          ))}
        </div>
        <div className="rowflex" style={{ marginTop: 10 }}>
          <select aria-label="Add block" value="" onChange={e => { if (e.target.value) addMeetingBlock(id, e.target.value as BlockKind) }}
            style={{ border: '1px solid var(--border-strong)', background: 'var(--panel)', borderRadius: 8, padding: '3px 6px', fontSize: 11 }}>
            <option value="">+ Add block</option>
            {BLOCK_KINDS.map(k => <option key={k} value={k}>{BLOCK_LABEL[k]}</option>)}
          </select>
          <span className="tiny" style={{ marginLeft: 'auto' }}>Autosaved</span>
        </div>
      </Card>

      {open.length > 0 && (
        <Card title="Open actions" subtitle="Same gate as an opportunity: an owner, a date and a human decision.">
          {open.map(item => (
            <div key={item.id} className="between" style={{ padding: '6px 0', borderTop: '1px solid var(--border)' }}>
              <div>
                <div style={{ fontSize: 12 }}>{item.text || 'Untitled action'}</div>
                <div className="tiny">{item.owner || 'Unassigned'}{item.due ? ` · due ${new Date(item.due).toLocaleDateString('en-GB')}` : ''}</div>
              </div>
              <button className="btn small" onClick={() => promoteAction(item.id)} disabled={!item.owner}>Promote</button>
            </div>
          ))}
        </Card>
      )}

      <Card title="Linked in the graph" subtitle="This page is a node, not a silo.">
        <KV items={[
          ['Meeting node', <span className="mono">{meeting.kgId}</span>],
          ['Process', process?.name ?? 'Not linked'],
          ['Initiative', initiative?.title ?? 'Not linked'],
          ['Decisions', `${decisions.length} recorded`],
          ['Actions', `${items.filter(b => b.kind === 'action').length} total · ${open.length} open`],
        ]} />
        <div className="rowflex" style={{ marginTop: 10 }}>
          <button className="btn small" onClick={() => { selectNode(meeting.kgId); navigate('graph') }}>Open meeting node</button>
          {process && <button className="btn small" onClick={() => navigate('discoveries')}>Open process</button>}
          {selectedNode === meeting.kgId && <Chip tone="blue">Selected</Chip>}
        </div>
        <Note>Attendees are roles, never people. Meeting notes are process evidence, not an attendance or performance record.</Note>
      </Card>
    </div>
  )
}
