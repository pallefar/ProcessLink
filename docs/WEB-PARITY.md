# Web parity with the macOS app

The web form is the TEOA Advantage sub-app replacement. It now uses the same
shell, density, type scale, colour tokens and page structure as ProcessLink
for macOS, so switching between the app and the browser does not feel like
switching products.

## 1. What is shared

| Layer | macOS | Web |
|---|---|---|
| Window | 216 pt sidebar, 52 pt toolbar, 20 pt content margin | 216 px sidebar, 52 px toolbar, 20 px content |
| Type | SF Pro 13 pt body, 22 pt page title, 26 pt metric | system stack 13 px body, 22 px page title, 26 px metric |
| Colour | system blue accent, white/`#f5f5f7` surfaces, dark `#1d1d1f` panels | same values as CSS tokens |
| Cards | 12 pt radius, hairline border, 16 pt inset, 13 pt heading | same |
| Sidebar | Flightdeck context, then Work / Improve / Trust, icon + label + count, governance footer | same, with the Flightdeck workspace/project and OS/Atlas/Vision links |
| Toolbar | page title, sandbox chip, sync / Ask / export / theme icon buttons | same actions and placement |
| Split panes | 260–330 pt list + detail, selected row tinted | same, responsive collapse under 1180 px |
| Chips | 11 px, rounded, tinted by state | same |
| Segmented control | macOS segmented picker | same shape and selected pill |
| Empty states | `ContentUnavailableView` with one action | same title + action layout |

The icon set is a hand-drawn line set matched to the SF Symbols used in the
app (grid, search, bulb, map, people, sparkle, flag, chat, hexagon, shield),
so navigation reads the same at a glance.

## 2. Page-by-page

| Page | Mac | Web |
|---|---|---|
| Overview | metrics, priority queue, pipeline, freshness, launch posture | same composition |
| Strategy | vision, bets, KPIs, values, initiative alignment | same read-only composition; editing is in the Mac app |
| Discoveries | process list + steps, variants, provenance | same |
| Opportunities | ranked list + score arithmetic, method, evidence | same |
| Maps | full-width Flightdeck map, Mine, Map fields / ProcessLink / drift bar | layout and map context; the live contract-flow mining path is macOS-only |
| Meetings | Notion-style pages with typed blocks, decisions, actions | same |
| Mining | Process logs / Task capture, mapped import, filters, process graph, cases, conformance, insights, simulation | **full log-mining workbench**; task capture remains desktop-only |
| Improvements | ledger, initiatives, A3, savings lifecycle | same |
| Feedback | threaded annotations + inbox | macOS-first; web feedback inbox is next |
| Agent / AI / OCEL / handoff | local policy, transformers.js, object graph, package | macOS-first in this release |
| Ask | guard chips, suggestions, policy card, bottom composer | same |
| Knowledge Graph | metrics, layered graph canvas, review queue, node list/detail | same canvas in SVG |
| Governance | readiness checks, classification, audit | same |

## 3. Deliberate differences

- **Map saving.** The Mac app writes the `signavio-map/1` document through the
  folder bridge or host API. The web form currently keeps the edit as a local
  proposal and records the intent; the host `PUT` with `If-Match` is the next
  step.
- **Mining.** The web workbench now imports CSV, filters, discovers a DFG,
  explores cases, runs conformance/root-cause and simulates. Task capture is
  still desktop-only: a browser cannot read other applications, so the web
  capture tab explains where capture runs instead of pretending otherwise.
- **Ask provider.** The web form is a visual/state prototype; it uses the same
  rule engine and seeded facts, not a live hosted model.
- **Graph scope.** The canvas shows the working set by layer (process,
  opportunity, initiative, meeting, objective), not all 104 nodes at once;
  the list and detail stay complete.

## 4. Preview

```bash
cd web
npm install
npm run dev          # http://localhost:5173
npm run build        # tsc --noEmit + vite build
npm run preview -- --port 4181
```

Deep links: `#/mining`, `#/maps`, `#/graph`; `?theme=light|dark`;
`?q=...` seeds the Ask question.

## 5. Screenshots

| | |
|---|---|
| ![Web overview](shots/web-overview.png) | ![Web maps](shots/web-maps.png) |
| ![Web mining](shots/web-mining.png) | ![Web graph](shots/web-graph.png) |

Dark mode: `shots/web-maps-dark.png`, `shots/web-mining-dark.png`,
`shots/web-ask-dark.png`.
