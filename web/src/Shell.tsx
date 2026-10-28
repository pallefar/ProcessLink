import type { ReactNode } from 'react'
import { NAV, useApp } from './App'
import Overview from './pages/Overview'
import Discoveries from './pages/Discoveries'
import Opportunities from './pages/Opportunities'
import Maps from './pages/Maps'
import Meetings from './pages/Meetings'
import Graph from './pages/Graph'
import Improvements from './pages/Improvements'
import Ask from './pages/Ask'
import Governance from './pages/Governance'

const PAGES = {
  overview: Overview,
  discoveries: Discoveries,
  opportunities: Opportunities,
  maps: Maps,
  meetings: Meetings,
  graph: Graph,
  improvements: Improvements,
  ask: Ask,
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
            <span>KYP.ai → TEOA</span>
          </div>
        </div>
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
                  <span className="nav-icon" aria-hidden="true">{item.icon}</span>
                  {item.label}
                  {item.id === 'opportunities' && <span className="count">{opportunities.filter(o => o.status === 'new').length}</span>}
                  {item.id === 'governance' && <span className="count">{governance.filter(g => g.status === 'blocked').length}</span>}
                </button>
              ))}
            </div>
          ))}
        </nav>
        <div className="side-foot">
          <strong>Improvement only</strong>
          <span>Groups ≥ {policy.minimumGroupSize} · {policy.region} · sandbox data</span>
        </div>
      </aside>

      <main className="main">
        <div className="topbar">
          <div className="crumb">ProcessLink / <strong>{active?.label ?? 'Overview'}</strong></div>
          <Chip tone="orange">Sandbox</Chip>
          <div className="spacer" />
          <button className="btn" onClick={sync}>↻ Sync</button>
          <button className="btn" onClick={exportBrief}>↑ Export brief</button>
          <button
            className="btn"
            onClick={() => setTheme(theme === 'auto' ? 'light' : theme === 'light' ? 'dark' : 'auto')}
            aria-label={`Theme: ${theme}`}
            title={`Theme: ${theme}`}
          >
            ◐ {theme === 'auto' ? 'Auto' : theme === 'light' ? 'Light' : 'Dark'}
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
