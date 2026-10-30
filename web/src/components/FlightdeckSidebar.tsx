import { useEffect, useState } from 'react'
import { useApp } from '../App'
import { osGet } from '../domain/osBridge'
import { Icon } from './Icon'

const OS_URL = (import.meta.env.VITE_FLIGHTDECK_URL as string | undefined) || 'http://127.0.0.1:4173'
const ATLAS_URL = (import.meta.env.VITE_ATLAS_URL as string | undefined) || 'http://localhost:5173'
const VISION_URL = `${OS_URL.replace(/\/$/, '')}/console/vision?standalone=1`

/** Host context and direct links. The selectors are display context for the
 * mounted TEOA sub-app; the OS remains the source of truth for membership. */
export function FlightdeckSidebar() {
  const { hostWorkspace, hostProject } = useApp()
  const [open, setOpen] = useState(true)
  const [workspace, setWorkspace] = useState(hostWorkspace || 'TE Operations')
  const [project, setProject] = useState(hostProject || 'Project Contract')
  const [projects, setProjects] = useState<Array<{ id: string; label: string }>>([])
  const [workspaceId, setWorkspaceId] = useState(hostWorkspace || '')
  useEffect(() => {
    void osGet<{ workspaceId: string; projects: Array<{ id: string; label: string }> }>('/api/projects').then(value => {
      if (!value) return
      setWorkspaceId(value.workspaceId)
      setProjects(value.projects.map(item => ({ id: item.id, label: item.label })))
      if (hostProject && value.projects.some(item => item.id === hostProject)) setProject(value.projects.find(item => item.id === hostProject)!.label)
    })
  }, [hostProject])

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
              {workspace !== 'TE Operations' && <option>{workspace}</option>}
              <option>TE Operations</option>
            </select>
            <span className="fd-chevron" aria-hidden="true">⌄</span>
          </label>
          <label className="fd-select-row">
            <Icon name="folder" size={13} />
            <select value={project} onChange={e => {
              setProject(e.target.value)
              const item = projects.find(p => p.label === e.target.value)
              try { if (item) localStorage.setItem('flightdeck.project', item.id) } catch { /* ignore */ }
            }} aria-label="Flightdeck project">
              {projects.length === 0 && <option>Project Contract</option>}
              {projects.map(item => <option key={item.id} value={item.label}>{item.label}</option>)}
              <option>General</option>
              <option>Cockpits</option>
            </select>
            <span className="fd-chevron" aria-hidden="true">⌄</span>
          </label>
          <div className="fd-links">
            <a href={OS_URL} target="_blank" rel="noreferrer" title="Flightdeck OS"><Icon name="macwindow" size={12} />OS</a>
            <a href={ATLAS_URL} target="_blank" rel="noreferrer" title="Atlas"><Icon name="layers" size={12} />Atlas</a>
            <a href={VISION_URL} target="_blank" rel="noreferrer" title="Vision"><Icon name="vision" size={12} />Vision</a>
          </div>
          <div className="fd-caption">{hostWorkspace ? 'OS host' : 'UAT'} · {workspaceId || workspace} · {project}</div>
        </div>
      )}
    </div>
  )
}
