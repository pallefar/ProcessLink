# ProcessLink

**The in-house discovery and value layer for TE Operating Advantage.**
ProcessLink mines event logs and opt-in task capture locally, then turns the
result into prioritized, owned, evidence-backed TEOA work, live maps,
knowledge-graph facts and DeckForge reports. No external discovery tenant is
required.

```
Event logs · task capture  →  ProcessLink  →  KG · Maps · TEOA · DeckForge
        (in-house)              (value layer)         (the work)
```

## The three forms

| Form | Where | Status |
|---|---|---|
| **macOS** — native SwiftUI + SwiftData | [`macos/ProcessLink`](macos/ProcessLink) | Built, 40 unit tests + 73 in-app checks, light/dark snapshots |
| **Web** — React 19 + Vite, strict TS | [`web`](web) | Same shell, full log-mining workbench, tokens and pages; the sub-app replacement is in [`web/src/flightdeck`](web/src/flightdeck) |
| **Windows** — Tauri 2 + WebView2 | [`windows/ProcessLink.Windows`](windows/ProcessLink.Windows) | Scaffolded with config and Rust entry; not built on a Windows host here |

Shared domain rules (privacy guard, opportunity scoring, savings ledger,
citation-first answer engine) live twice on purpose — Swift in
`ProcessLinkKit`, TypeScript in `web/src/domain` — and are verified against
the same behaviour in both test suites. See [`packages/README.md`](packages/README.md).

## What it does

1. **Strategy** — one function vision, a small set of strategic bets, defined
   KPIs with baseline/current/target and a source, and values with behavioural
   anchors. Every initiative is linked to a bet, a KPI, at least one value and
   a vision contribution; stage and saving gates block until it is.
2. **Discovery** — processes, variants, steps, roles, applications and
   metrics arrive from in-house event-log mining or task capture, as
   aggregates with provenance. Window titles, local screenshots and
   keystroke/click counts are opt-in; no clipboard, key codes, person ids or
   Restricted content.
3. **Opportunity** — each waste pattern is scored from mined hours, error
   reduction, effort, risk, Hoshin alignment and confidence. The route follows
   TEOA order: eliminate → simplify → standardize → automate. Statutory and
   human-only steps are never automation candidates.
4. **Improvement** — a promoted opportunity becomes an A3/kaizen initiative
   with an owner, a stage and a saving that moves estimated → committed →
   validated. Validation needs a named human and before/after evidence.
5. **Maps** — ProcessLink imports every map from the connected Flightdeck
   Maps projects and reads/writes real `signavio-map/1` documents. Shapes carry
   a `processLink` binding, so the map inspector shows the mined step,
   opportunity and saving; map edits come back as drift and audited proposals.
   Overlays cover cycle time, handoffs, rework and automation potential.
6. **Graph** — typed nodes and edges with confidence, validity and source; a
   human review queue for uncertain matches; no silent merges.
7. **Ask** — a governed assistant over the same facts. Every number cites a
   discovery id or KG node; gaps become a "to verify" list; savings stay labelled
   estimates.
8. **Meetings** — Notion-style pages made of typed blocks (headings, bullets,
   to-dos, decisions, actions, callouts). Decisions and actions become graph
   facts; an action can be promoted to an initiative through the same gate as
   an opportunity. Templates cover daily huddles, kaizen, A3 reviews,
   leadership reviews and workshops.
9. **Mining** — a full in-house process-mining workbench:
   mapped CSV import with attributes and cost, filters, weekly throughput,
   variants, a directly-follows process graph, a case explorer with timelines,
   token-replay and sequence conformance, root-cause comparisons, a what-if
   simulator, capacity/queue simulation, a sound process tree with BPMN export,
   optimal alignment, a watchlist, view-vs-baseline comparison, bulk folder
   import and CSV/JSON export. Or run a local task capture (frontmost app, minutes and
   switches by default; optional window titles, local screenshots and
   keystroke/click counts). Mined
   results become the same process/KG/map/opportunity records. Configured REST
   connectors pull ServiceNow, Salesforce, SAP or generic JSON through a
   Keychain-held credential and the same field mapping.
10. **Connections** — a real UAT API connection to Flightdeck OS, Vision and
   Atlas. The sidebar carries the Flightdeck workspace/project dropdowns and
   direct **OS / Atlas / Vision** links; UAT quick-login accounts are listed
   without passwords and the session cookie lives in the Keychain. Workspaces,
   projects, 14 KPIs, ranked opportunities, Vision goals/roadmap and Atlas
   projects are read into the graph — read-only, no writes back.
11. **Governance** — purpose limitation, group-size suppression, classification
    refusal, PII masking and an audit log are enforced in code and visible in
    the UI. The launch checklist blocks production.

## Screenshots

| Strategy | Overview |
|---|---|
| ![Strategy](docs/shots/strategy-light.png) | ![Overview](docs/shots/overview-light.png) |

| Process map | Opportunities |
|---|---|
| ![Flightdeck map with ProcessLink inspector](docs/shots/maps-light.png) | ![Opportunities](docs/shots/opportunities-light.png) |

| Knowledge graph | Mining workbench |
|---|---|
| ![Graph](docs/shots/graph-light.png) | ![Mining](docs/shots/mining-light.png) |

| Process graph | Case explorer |
|---|---|
| ![Process graph](docs/shots/mining-process-light.png) | ![Cases](docs/shots/mining-cases-light.png) |

| What-if simulation | Task capture |
|---|---|
| ![Simulate](docs/shots/mining-simulate-light.png) | ![Task capture](docs/shots/mining-capture-light.png) |

| Conformance | Connections |
|---|---|
| ![Conformance](docs/shots/mining-conformance-light.png) | ![Connections](docs/shots/connections-light.png) |

| Meetings | Governance |
|---|---|
| ![Meetings](docs/shots/meetings-light.png) | ![Governance](docs/shots/governance-light.png) |

| Ask the process | Web overview |
|---|---|
| ![Ask](docs/shots/ask-light.png) | ![Web overview](docs/shots/web-overview.png) |

| Web strategy | Web maps |
|---|---|
| ![Web strategy](docs/shots/web-strategy.png) | ![Web maps](docs/shots/web-maps.png) |

| Web mining | Web graph |
|---|---|
| ![Web mining](docs/shots/web-mining.png) | ![Web graph](docs/shots/web-graph.png) |

More in [`docs/shots`](docs/shots), including dark mode and Settings. The
design parity contract is in [`docs/WEB-PARITY.md`](docs/WEB-PARITY.md).

## Run the macOS app

```bash
cd macos/ProcessLink
./build.sh --open          # release build, installs ~/Applications/ProcessLink.app
tools/selftest.sh          # 73 checks, exit 0
tools/snap.sh              # light/dark PNGs of every page + Settings
swift test --scratch-path ~/Library/Developer/ProcessLink/test-build
```

Requires macOS 26+ and Swift 6.2 (the build machine used macOS 27 and Swift
6.4). The app is local-first: SwiftData at
`~/Library/Application Support/ProcessLink`, no server.

**OS integration:** Option-Command-P opens the Ask panel from any app; a menu
bar item stays available when the window is closed; `processlink://` deep links
open a record; sync notifications are opt-in; the review brief exports as
Markdown.

## Run the web form

```bash
cd web
npm install
npm run dev        # http://localhost:5173
npm run build      # tsc --noEmit && vite build
```

Deep links: `#/overview`, `#/maps`, `#/opportunities`, `#/governance`…
Add `?theme=light|dark` and `?q=...` for screenshots and demos.

The app is designed to mount as a Flightdeck sub-app. The adapter, manifest,
routes and migration sketch are in [`web/src/flightdeck`](web/src/flightdeck);
read that before replacing the `advantage` sub-app in the host.

## Run the Windows shell

See [`windows/ProcessLink.Windows/README.md`](windows/ProcessLink.Windows/README.md).
It wraps `web/dist`; build on Windows 11 with Rust + WebView2.

## Demo path (5 minutes)

1. **Overview** — 12,710 h of discovered effort, 540 h validated, one
   double-count warning.
2. **Discoveries** — open *Order intake & validation*; see variants, steps,
   provenance. Then open *Contract clause review* (suppressed, group of 8) and
   *Export control screening* (Restricted, blocked).
3. **Opportunities** — open *Remove the duplicate pricing check*; read the
   score arithmetic and the recommended method. **Start initiative**.
4. **Improvements** — move the stage, commit the saving, then **Validate**
   with a validator and evidence. Try validating without evidence first.
5. **Maps** — switch overlay to **Rework**; click a shape; open its KG node.
6. **Meetings** — open *Kaizen · pricing check in order intake*; read the
   decisions, promote an action, then open the meeting node in the graph.
7. **Ask** — ask *"Where do handoffs create the most rework?"* and *"What did
   we decide about pricing?"*; open a citation; read the to-verify line.
8. **Governance** — press *Send Restricted to the AI gateway* and *Export a
   4-person group*; read the refusal and its rule.

## What is real, what is sandbox

- **Real**: the domain rules, the privacy guard, the scoring arithmetic, the
  savings ledger and its conflict rule, the graph algorithms, the citations,
  the audit trail, the meeting pages and the app itself.
- **Synthetic discovery data**: every process, person-count, hour, site and
  saving. No external discovery tenant was contacted. Configured connectors
  are read-only REST pulls and have no stored credential in the demo.
  The KG is a local typed store, not a write to Knowledge Guardian. DeckForge
  receives a Markdown/JSON brief, not a deck binary.

## Privacy and governance (non-negotiable)

ProcessLink touches data about how people work. It is for **process and
system improvement only**. There is no per-person drill-down, no leaderboard,
no individual performance use. Groups below the threshold (default 10) are
suppressed at display, export and AI time. Restricted content is refused at
the boundary. Personal-data patterns are masked before any hosted call. The
launch checklist — DPIA, country legal review, works-council consultation,
transparency notice, retention, named owner, approved AI regions — is in the
app and in [`docs/PHASE-0-DISCOVERY.md`](docs/PHASE-0-DISCOVERY.md).

**No production use until the checklist is signed.**

## Documentation

| Document | What it answers |
|---|---|
| [`docs/PHASE-0-DISCOVERY.md`](docs/PHASE-0-DISCOVERY.md) | Historical Phase 0 evidence and gap analysis; superseded by in-house discovery |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Three forms, shared packages, sync pipeline, gates, AI layer, performance, security boundaries |
| [`docs/KG-ONTOLOGY.md`](docs/KG-ONTOLOGY.md) | 25 node types, 15 relations, provenance, entity resolution, ACL, GraphRAG, migration plan M0–M6 |
| [`docs/RISKS-AND-MVP.md`](docs/RISKS-AND-MVP.md) | Feasibility/risk table, build-vs-buy with licence notes, MVP cut line, phase plan |
| [`docs/MAPS-INTEGRATION.md`](docs/MAPS-INTEGRATION.md) | The two-way `signavio-map/1` contract, schema extension, host routes, drift rules |
| [`docs/IN-HOUSE-DISCOVERY.md`](docs/IN-HOUSE-DISCOVERY.md) | The full in-house mining workbench, import/filter/case/conformance/root-cause/simulation, privacy boundary and limits |
| [`docs/WEB-PARITY.md`](docs/WEB-PARITY.md) | How the web form matches the macOS shell, tokens, pages and where it deliberately differs |
| [`docs/CONNECTIONS.md`](docs/CONNECTIONS.md) | Live UAT connection to OS, Vision and Atlas: sign-in, endpoints, graph mapping, security and limits |

## Releases

Tag a version and GitHub Actions builds both desktop installers:

```bash
git tag v0.1.7 && git push origin v0.1.7
```

The release contains a universal macOS DMG (`arm64` + `x86_64`), a Windows
NSIS setup (and an MSI from the Windows CI job), and `SHA256SUMS.txt`.
[Download v0.1.7](https://github.com/pallefar/ProcessLink/releases/tag/v0.1.7).
Local packaging, signing and the current Actions billing note are in
[`docs/RELEASING.md`](docs/RELEASING.md).

## Repository

```
ProcessLink/
  macos/ProcessLink/      SwiftUI app (Swift package, build.sh, tools)
  web/                    React + Vite app, domain rules, Flightdeck adapter
  windows/                Tauri 2 shell
  packages/               shared-package map
  docs/                   Phase 0, architecture, strategy, ontology, risks, screenshots
```

## Licence and IP

In-house code. Dependencies are MIT/Apache-2.0 (React, Vite, Tauri,
Transformers.js if used later); no GPL/AGPL is shipped. TE Operating
Advantage, DeckForge and DiagramForge are used under their existing
commercial/in-house terms. The TEOA method catalogue is a **draft** until the
official TE definitions are confirmed.
