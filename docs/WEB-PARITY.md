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
| Sidebar | Work / Improve / Trust, icon + label + count, governance footer | same |
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
| Discoveries | process list + steps, variants, provenance | same |
| Opportunities | ranked list + score arithmetic, method, evidence | same |
| Maps | full-width Flightdeck map, bottom Map fields / ProcessLink / drift bar | same layout; edits are local proposals in this build |
| Meetings | Notion-style pages with typed blocks, decisions, actions | same |
| Mining | Process logs / Task capture, sample, variants, bottlenecks, conformance | same layout; sample data and capture explanation (see limits) |
| Improvements | ledger, initiatives, A3, savings lifecycle | same |
| Ask | guard chips, suggestions, policy card, bottom composer | same |
| Knowledge Graph | metrics, layered graph canvas, review queue, node list/detail | same canvas in SVG |
| Governance | readiness checks, classification, audit | same |

## 3. Deliberate differences

- **Map saving.** The Mac app writes the `signavio-map/1` document through the
  folder bridge or host API. The web form currently keeps the edit as a local
  proposal and records the intent; the host `PUT` with `If-Match` is the next
  step.
- **Mining import.** The web sample mirrors the Mac sample result. CSV import
  and live task capture are desktop features; a browser cannot read other
  applications, and duplicating the capture path in the web form would
  misrepresent what it can see.
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
