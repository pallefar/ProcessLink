# Feasibility, risk, build-vs-buy, and the MVP cut line

## 1. Feasibility and risk

| Area | Risk | Likelihood | Impact | Mitigation in this build | Still open |
|---|---|---|---|---|---|
| KYP.ai API coverage | The licensed modules may not expose steps/variants/metrics through a supported interface; MCP may be the only path | Medium | High | Connector is a thin, replaceable adapter; every fact has a source id; fixtures stand in for the API | Q1, Q2 — module list + sandbox contract |
| KYP.ai person-level data | API returns person rows; aggregation must happen inside the tenant | Medium | High | Connector drops person ids and counts the drop; guard refuses below threshold | Q9 — confirm aggregate scope |
| Entity-resolution quality | Application/role names differ between KYP and the registry; silent merges corrupt the graph | High | High | Confidence bands; ≥ 0.90 auto-link, 0.70–0.89 review queue, < 0.70 new node; merge is reversible with `validTo` | Precision measurement on a real sample |
| Savings double counting | Two initiatives claim the same hours; leadership roll-up overstates | High | High | One claim per (process, waste) key; credits only the most advanced claim; conflicts surfaced with both numbers; validation needs a named human | Q6 — TE validation rules + Finance ownership |
| Works council / GDPR | Capture expansion before consultation; no DPIA for production | Medium | Very high | Purpose limitation first; group thresholds; no person drill-down; launch checklist blocks production | Q3, Q4 — DPIA, consultation, country legal review |
| Classification / export control | A Restricted record reaches an API or deck | Low | Very high | `restricted` blocked at every destination including local; refusal audited; no export path | Data-classification mapping from the real tenant |
| Local-model limits | On-device model too weak for GraphRAG answers; users lose trust | Medium | Medium | Local provider is deterministic and citation-checked; hosted option is explicit; answers degrade to retrieval + template | Benchmark on the approved local model |
| TEOA definitions | Generic lean text shipped as "TEOA" | High | Medium | Catalogue labelled **draft** everywhere; no official claims; methods are data | Q4 — official tool list |
| Map scale | 500-node map unreadable/ slow | Medium | Medium | Column layout with horizontal scroll; generation target < 5 s; overlays computed once | Real 500-node fixture |
| KG store mismatch | Target is RDF or a vendor graph, not the assumed property graph | Medium | High | `kg-client` isolates the store; ontology is transport-neutral; proposal only | Q5 — real store and ACL |
| Windows build | No Windows host to verify Tauri packaging | High | Low | Scaffold only; web bundle is the shared artifact | CI on Windows |
| DeckForge coupling | Deck schema changes break report generation | Low | Medium | Brief is Markdown/JSON first; deck adapter is optional | Template contract review |
| Adoption | CI managers keep using spreadsheets | Medium | Medium | The app starts from their existing artefacts (A3, board, X-matrix) and adds discovery; no new taxonomy to learn | Pilot at one site |

### 1.1 The two risks that decide the product

1. **Works council and DPIA.** If consultation is not concluded, nothing
   ships, regardless of code quality. The product must be able to run a
   **pilot with aggregate-only data** and prove value before asking for more.
2. **Savings credibility.** One inflated number destroys trust with Finance.
   The ledger's conservative rule (credit once, validate with evidence) is
   the product's spine, not a feature.

## 2. Build vs buy

| Need | Build | Buy / reuse | Decision | Licence note |
|---|---|---|---|---|
| Task/process mining capture | — | **KYP.ai** | Buy; ProcessLink never captures | Commercial SaaS; data-processing agreement required |
| Iterative graph store | Local typed store for the prototype | Existing KG when Q5 is answered | Reuse the KG; do not run a second graph | Depends on real store |
| Vector search | — | Existing `kb_vectors` pattern (brute-force cosine / `sqlite-vec`) | Reuse | `sqlite-vec` MIT/Apache-2.0 |
| Charting (web) | Small SVG/CSS marks | No chart library in this build | Build; revisit if needed | Avoid AGPL charting libs |
| Flow canvas | Read-only SVG in this build | DiagramForge (`@xyflow/react`) | Reuse DiagramForge for editing | MIT |
| AI provider | Citation-checked deterministic engine | `ai-core` + Anthropic Claude | Reuse gateway; local fallback | Anthropic commercial terms; Transformers.js Apache-2.0 |
| Deck generation | Markdown brief | DeckForge | Reuse | In-house |
| Desktop shell (Windows) | Tauri 2 | Tauri | Reuse | MIT / Apache-2.0 |
| Auth / SSO | — | Flightdeck | Reuse | In-house |
| Scheduling / queue | In-process scheduler for the prototype | Flightdeck ingest queue | Reuse | In-house |
| Icons | SF Symbols | Apple | Reuse | Apple licence |

**Licence policy:** no GPL/AGPL in shipped code; flag copyleft in CI; SBOM per
release. The only AGPL-adjacent candidate (a graph database with an AGPL
community edition) is explicitly rejected until legal reviews it.

## 3. MVP cut line

### In the MVP (this build)

- macOS app with 8 pages, seeded sandbox data, keyboard and menu coverage.
- Purpose limitation, classification gate, group threshold, PII masking,
  audit log, launch checklist.
- Opportunity scoring with explainable components, route and method.
- Initiative + A3 + savings lifecycle with evidence and double-count guard.
- Generated swimlane map with three overlays and KG-bound shapes.
- KG explorer with a layered canvas, focus/neighbourhood, search, quality
  filters, provenance, backlinks and a human review queue.
- Notion-style meeting pages with typed blocks, decisions, actions, templates,
  process/initiative links, and write-through to the graph.
- Ask with citations, to-verify list and confidence.
- Web form with the same domain rules and the core pages.
- Windows Tauri scaffold.
- Phase 0 discovery, ontology proposal, risk table, this cut line.

### Deliberately out (next)

- Live KYP.ai connector and contract tests (needs Q1/Q2).
- Real KG writes and migration (needs Q5).
- Editing maps in ProcessLink (DiagramForge owns editing).
- DeckForge binary integration and TE templates (needs deck contract).
- Flightdeck SSO + Mini App packaging (needs Q10).
- Multi-user collaboration, presence, comments, real-time co-editing.
- Scheduled background sync while the app is closed.
- Model-hosted GraphRAG (the gateway exists in `ai-core`; not wired here).
- Mobile.

### Phase plan after approval

| Phase | Deliverable | Gate |
|---|---|---|
| 1 | Connector against a real sandbox; `process-model` contract tests | Q1, Q2; read-only token |
| 2 | KG migration M1–M3; review queue; point-in-time queries | Q5; ontology approval |
| 3 | DiagramForge `kgNodeId` + generation worker; drift detection | Map schema review |
| 4 | TEOA method catalogue with official definitions; waste classification | Q4 |
| 5 | Savings validation with Finance; roll-ups; change packages | Q6; Finance sign-off |
| 6 | Hosted GraphRAG; agents; MCP server; evaluation harness | Q7; security review |
| 7 | DeckForge templates + one-click decks | Deck contract |
| 8 | Flightdeck Mini App, SSO, Windows packaging | Q10; Windows CI |
| 9 | Privacy/security review, accessibility, pilot, rollout | DPIA + works council |

## 4. Definition of done for the MVP

- Build has zero warnings; 17 unit tests and 26 in-app checks pass.
- Every page has light and dark snapshots reviewed.
- A refusal is demonstrable in three places (restricted, small group, PII).
- A saving cannot reach "validated" without a named validator and evidence.
- Every number shown in Ask has a citation or a to-verify item.
- No secret, tenant id or person name appears in the repository or the demo data.
