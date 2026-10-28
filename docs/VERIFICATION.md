# Verification record

Run on macOS 27.0.1, Swift 6.4, Xcode 27.1, Node 22.23.3, 28 October 2026.

## macOS app

| Check | Command | Result |
|---|---|---|
| Build (release) | `./build.sh` | `Build complete!`, 0 errors, 0 warnings, installed to `~/Applications/ProcessLink.app` |
| Unit tests | `swift test --scratch-path ~/Library/Developer/ProcessLink/test-build` | **27 tests passed** (scoring, statutory guard, privacy, PII, ledger, conflicts, ask citations, formatting, graph algorithms, CSV import/mining/conformance) |
| In-app self-test | `tools/selftest.sh` | **SELFTEST PASS 64 checks** |
| Grid lint | `tools/grid-lint.sh` | **PASS** |
| Layout probes | `swift tools/check-layout.swift /tmp/ProcessLink-shots/*-layout.json` | **22 PASS**, 0 fail |
| Snapshots | `tools/snap.sh` | 8 pages + 5 Settings tabs, light and dark, 2520×1640 page PNGs; reviewed |
| Activation | snapshot script brings the app forward before capture | Traffic lights/key state verified; inactive-window captures rejected |

Self-test coverage: seed integrity, Restricted refusal, group-size
suppression, purpose limitation, PII detection and masking, score monotonicity
and bounds, statutory route exclusion, ledger credit-once rule, double-count
detection, handoff citation, promotion, commit-before-validate, evidence
requirement, blocked promotion, sync + audit, human entity-resolution merge
(with edge re-pointing), "restricted process never enters the ask context",
meeting pages and blocks, meeting/decision graph nodes and edges, action
promotion, decision answers citing a meeting, the Maps document contract
(schema, bindings, drift, persistence, map KG node/edge), and in-house
discovery (sample import, hashed cases, 24-case mining, three variants,
process creation, capture aggregates and capture-to-process).

## Web app

| Check | Command | Result |
|---|---|---|
| Typecheck + build | `npm run build` | `tsc --noEmit` clean; Vite build 353 kB JS / 14.9 kB CSS (≈106 kB gzip) |
| Render review | headless Chrome, 1440×1000 | Overview, Discoveries, Opportunities, Maps, Meetings, Graph, Improvements, Ask, Governance; light and dark |
| Deep links | `#/overview`, `?theme=light|dark`, `?q=...` | Verified via screenshots |
| Local preview | `npm run preview` on port 4175 | 200 OK |

The web form uses the same seed facts and the same rule set as the app. It is
not connected to a host API in this build; the adapter in
`web/src/flightdeck` defines the seam.

## Windows

Scaffolded only. `tauri.conf.json`, `Cargo.toml`, `lib.rs`, `main.rs` and the
capability file are complete, but **no Windows build was run** (this machine
is macOS). See `windows/ProcessLink.Windows/README.md` for the honest status
and the build commands.

## Deliberately not verified

- A live Flightdeck Maps server (the folder bridge writes the same documents;
  the host routes are documented in `MAPS-INTEGRATION.md`).
- A real KYP.ai tenant (no credentials, no tenant; Q1/Q2 unanswered).
- A real Knowledge Guardian write (no store/ACL; Q5 unanswered).
- DeckForge binary integration (Markdown brief only).
- Flightdeck sub-app mount (adapter + migration sketch, not applied).
- Works-council, DPIA, legal sign-off (governance checklist only).

## Screenshot inventory

`docs/shots/` contains macOS light/dark pages, two Settings tabs, and three
web captures. Raw snapshots remain in `/tmp/ProcessLink-shots/` on the build
machine.
