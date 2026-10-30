import type { ReactNode } from 'react'
import { NAV, useApp } from './App'
import Overview from './pages/Overview'
import Strategy from './pages/Strategy'
import Discoveries from './pages/Discoveries'
import Opportunities from './pages/Opportunities'
import Maps from './pages/Maps'
import Meetings from './pages/Meetings'
import Graph from './pages/Graph'
import Improvements from './pages/Improvements'
import Ask from './pages/Ask'
import Feedback from './pages/Feedback'
import Mining from './pages/Mining'
import Governance from './pages/Governance'
import { Icon } from './components/Icon'
import { FlightdeckSidebar } from './components/FlightdeckSidebar'

const PAGES = {
  overview: Overview,
  strategy: Strategy,
  discoveries: Discoveries,
  opportunities: Opportunities,
  maps: Maps,
  meetings: Meetings,
  mining: Mining,
  graph: Graph,
  improvements: Improvements,
  ask: Ask,
  feedback: Feedback,
  governance: Governance,
}

export function Shell() {
  const { page, navigate, toast, policy, opportunities, governance, sync, exportBrief, theme, setTheme } = useApp()
  const Current = PAGES[page]
  const groups = ['Work', 'Improve', 'Trust']
  const active = NAV.find(item => item.id === page)

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark" aria-hidden="true">PL</div>
          <div>
            <strong>ProcessLink</strong>
            <span>Discovery → TEOA</span>
          </div>
        </div>
        <FlightdeckSidebar />
        <nav className="nav" aria-label="Sections">
          {groups.map(group => (
            <div key={group}>
              <div className="nav-label">{group}</div>
              {NAV.filter(item => item.group === group).map(item => (
                <button
                  key={item.id}
                  className="nav-item"
                  aria-current={page === item.id ? 'page' : undefined}
                  onClick={() => navigate(item.id)}
                >
                  <span className="nav-icon" aria-hidden="true"><Icon name={item.icon as never} /></span>
                  {item.label}
                  {item.id === 'opportunities' && <span className="count">{opportunities.filter(o => o.status === 'new').length}</span>}
                  {item.id === 'governance' && <span className="count">{governance.filter(g => g.status === 'blocked').length}</span>}
                </button>
              ))}
            </div>
          ))}
        </nav>
        <div className="side-foot">
          <span className="foot-shield"><Icon name="governance" size={13} /> Improvement only · ≥ {policy.minimumGroupSize} · {policy.region}</span>
        </div>
      </aside>

      <main className="main">
        <div className="topbar">
          <h1 className="topbar-title">{active?.label ?? 'Overview'}</h1>
          <Chip tone="orange">Local</Chip>
          <div className="spacer" />
          <button className="icon-btn" onClick={sync} aria-label="Sync sources" title="Sync sources"><Icon name="sync" size={16} /></button>
          <button className="icon-btn" onClick={() => navigate('ask')} aria-label="Ask ProcessLink" title="Ask ProcessLink"><Icon name="ask" size={16} /></button>
          <button className="icon-btn" onClick={exportBrief} aria-label="Export brief" title="Export brief"><Icon name="export" size={16} /></button>
          <button
            className="icon-btn"
            onClick={() => setTheme(theme === 'auto' ? 'light' : theme === 'light' ? 'dark' : 'auto')}
            aria-label={`Theme: ${theme}`}
            title={`Theme: ${theme}`}
          >
            <Icon name="theme" size={16} />
          </button>
        </div>
        <div className="content">
          <Current />
        </div>
      </main>

      {toast && (
        <div className="toast" role="status">
          <span aria-hidden="true">{toast.warning ? '▲' : '✓'}</span>
          <strong>{toast.title}</strong>
          {toast.detail && <span>{toast.detail}</span>}
        </div>
      )}
    </div>
  )
}

// Local copy of the chip used by the shell (kept here to avoid a cycle).
function Chip({ children, tone }: { children: ReactNode; tone?: 'orange' }) {
  return <span className="chip" data-tone={tone}>{children}</span>
}
