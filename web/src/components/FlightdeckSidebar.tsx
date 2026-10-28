import { useState } from 'react'
import { Icon } from './Icon'

const OS_URL = (import.meta.env.VITE_FLIGHTDECK_URL as string | undefined) || 'http://127.0.0.1:4173'
const ATLAS_URL = (import.meta.env.VITE_ATLAS_URL as string | undefined) || 'http://localhost:5173'
const VISION_URL = `${OS_URL.replace(/\/$/, '')}/console/vision?standalone=1`

/** Host context and direct links. The selectors are display context for the
 * mounted TEOA sub-app; the OS remains the source of truth for membership. */
export function FlightdeckSidebar() {
  const [open, setOpen] = useState(true)
  const [workspace, setWorkspace] = useState('TE Operations')
  const [project, setProject] = useState('Project Contract')

  return (
    <div className="fd-sidebar">
      <button className="fd-head" onClick={() => setOpen(v => !v)} aria-expanded={open}>
        <span className={`fd-chevron ${open ? 'open' : ''}`} aria-hidden="true">›</span>
        <Icon name="cloud" size={14} />
        <span>Flightdeck</span>
        <span className="fd-dot" title="Host context available" />
      </button>
      {open && (
        <div className="fd-body">
          <label className="fd-select-row">
            <Icon name="layers" size={13} />
            <select value={workspace} onChange={e => setWorkspace(e.target.value)} aria-label="Flightdeck workspace">
              <option>TE Operations</option>
            </select>
          </label>
          <label className="fd-select-row">
            <Icon name="folder" size={13} />
            <select value={project} onChange={e => setProject(e.target.value)} aria-label="Flightdeck project">
              <option>Project Contract</option>
              <option>General</option>
              <option>Cockpits</option>
            </select>
          </label>
          <div className="fd-links">
            <a href={OS_URL} target="_blank" rel="noreferrer"><Icon name="macwindow" size={12} />Flightdeck OS</a>
            <a href={ATLAS_URL} target="_blank" rel="noreferrer"><Icon name="layers" size={12} />Atlas</a>
            <a href={VISION_URL} target="_blank" rel="noreferrer"><Icon name="vision" size={12} />Vision</a>
          </div>
          <div className="fd-caption">UAT · {workspace} · {project}</div>
        </div>
      )}
    </div>
  )
}
