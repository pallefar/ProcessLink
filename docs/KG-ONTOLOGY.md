# Knowledge graph ontology — proposal `processlink-kg/1`

**State:** proposal. No migration has been applied to a real Knowledge
Guardian store. The local prototype implements these types so the contract
can be exercised; the migration plan below is the gate.

## 1. Why a new layer

Knowledge Guardian holds **documents and their trained conversion specs**.
`process-catalog/1` holds an **HR process hierarchy** keyed by entity scope.
Neither is a typed process graph with provenance. This proposal adds an
additive layer; nothing in the existing schema is renamed or dropped.

## 2. Nodes

| Kind | Identity | Required claims | Natural key |
|---|---|---|---|
| `Process` | discovery process id + site | name, value stream, owner role | `discovery:process/{id}` |
| `Subprocess` | parent + name | parent process | `pl:subprocess/{id}` |
| `Task` | discovery task id | parent step | `discovery:task/{id}` |
| `Step` | discovery step id / map node | role, application | `discovery:step/{id}` |
| `Variant` | discovery variant id | share, path | `discovery:variant/{id}` |
| `Application` | normalised app name | vendor optional | `registry:app/{slug}` |
| `System` | system of record | owner | `registry:system/{slug}` |
| `Role` | role name | site/team optional | `registry:role/{slug}` |
| `Team` | org unit | parent unit | `registry:team/{slug}` |
| `Site` | Flightdeck site code | country | `registry:site/{code}` |
| `BusinessUnit` | Flightdeck BU | — | `registry:bu/{code}` |
| `ValueStream` | catalogue value stream | — | `catalog:vs/{id}` |
| `Document` | KG doc/type id | version | `kg:doc/{id}` |
| `Control` | control id | statutory flag | `pl:control/{id}` |
| `Risk` | risk id | severity | `pl:risk/{id}` |
| `Metric` | metric key | unit, betterWhen | `pl:metric/{key}` |
| `PainPoint` | derived id | severity, evidence | `pl:pain/{id}` |
| `WasteInstance` | step + waste type + window | hours, evidence | `pl:waste/{step}/{type}/{window}` |
| `Opportunity` | derived id | score, route | `pl:opp/{id}` |
| `Initiative` | Advantage item id / A3 id | owner, stage | `adv:item/{id}` |
| `Automation` | change package id | risk class, approval | `pl:auto/{id}` |
| `SavingsRecord` | initiative + stage | hours, validator | `pl:savings/{id}` |
| `TEOAMethod` | method key | definition version | `teoa:method/{key}` |
| `MaturityAssessment` | focus + version | level | `adv:focus/{id}` |
| `HoshinObjective` | objective id | year | `adv:objective/{id}` |
| `Meeting` | meeting id | date, owner role | `pl:meeting/{id}` |
| `Decision` | block id | text, meeting | `pl:decision/{id}` |
| `Action` | block id | text, owner role, due | `pl:action/{id}` |

### 2.1 Required properties on every node

```ts
{
  id: string                 // stable, namespaced
  kind: KGKind
  name: string
  confidence: number         // 0..1, from the extractor
  validFrom: string          // ISO date
  validTo: string | null     // null = current
  source: string             // "ProcessLink discovery", "registry", "user:role"
  sourceId: string
  classification: DataClass  // public | internal | confidential | restricted
  groupSize: number | null   // for aggregates; drives suppression
  syncedAt: string
}
```

`validTo` plus `validFrom` gives point-in-time queries for free; the current
graph is `validTo == null`.

## 3. Edges

| Predicate | From → To | Notes |
|---|---|---|
| `performed_in` | Task/Step → Process/Site | site edge carries the org scope |
| `uses` | Step/Process → Application/System | confidence from mining |
| `hands_off_to` | Step → Step | carries queue time |
| `variant_of` | Variant → Process | share on the variant |
| `deviates_from_standard` | Step → Document | requires an SOP version |
| `owned_by` | Process/Initiative → Role/Team | role, never a person |
| `measured_by` | Process/Step → Metric | unit + window |
| `causes` | Step/PainPoint → WasteInstance | evidence counts |
| `mitigated_by` | Risk → Control | — |
| `addressed_by` | Opportunity → Initiative | one opportunity may have many |
| `automated_by` | Initiative → Automation | needs an approved change package |
| `realizes_savings` | Initiative → SavingsRecord | hours, stage |
| `aligned_to_objective` | Initiative/Opportunity → HoshinObjective | strength 1–3 |
| `documented_in` | Process/Step → Document | SOP version |
| `has_opportunity` | Process → Opportunity | ProcessLink extension |
| `discussed_in` | Process/Initiative → Meeting | Meeting page about the work |
| `assigned_to` | Action → Role | Owner is a role, never a person |

Every edge carries `confidence`, `source`, `validFrom`, `validTo`, and the id
of the extractor run. Decisions and actions are written when the block is
created and refreshed when it changes; the meeting page is the evidence.

## 4. Entity resolution

Deterministic, explainable, and never silent:

1. **Exact key** — registry code, discovery id, SOP id. Confidence 1.0.
2. **Normalised name** — case/space/punctuation folding, language variants.
3. **Alias table** — reviewed aliases, versioned.
4. **Fuzzy** — trigram similarity + token overlap, threshold 0.6.
5. **Context** — site, value stream and application overlap raise confidence.

| Score | Action |
|---|---|
| ≥ 0.90 | Auto-link, audited, reversible |
| 0.70–0.89 | **Review queue**; the node stays separate until confirmed |
| < 0.70 | New node, proposal only |

Merges are never destructive: the losing node gets `validTo`, a
`merged_into` note, and every edge is re-pointed in one transaction with a
content-hash idempotency key.

## 5. Access control

- Node ACL inherits Flightdeck's project/workspace permissions; ProcessLink
  adds no new grant.
- Query-time aggregation thresholds: a group below `minimumGroupSize` never
  returns metrics, only the fact of suppression.
- The KG client asks the guard **before** the request, and the server
  re-checks — defence in depth.
- `restricted` nodes are not written at all; the attempt is audited.

## 6. GraphRAG

1. Parse the question into entities + intent.
2. Resolve entities to candidate nodes (alias + embedding + context).
3. Traverse 1–2 hops along allowlisted predicates; rank by confidence and
   recency.
4. Hydrate metrics from discovery aggregates, subject to the group threshold.
5. Compose a context pack where every fact carries `(nodeId, sourceId,
   window)`.
6. Answer; validate that each number has a citation; emit `toVerify` for gaps.

Retrieval is hybrid: graph traversal for structure, vector search over SOPs
and document chunks for prose. The vector index is the existing `kb_vectors`
pattern, gated by `VECTOR_SEARCH_ENABLED`.

## 7. Data quality dashboard

| Signal | Rule |
|---|---|
| Orphan | No edge in either direction |
| Duplicate | Two nodes ≥ 0.90 similarity, different ids |
| Stale | `validTo == null` and `syncedAt` older than the entity's freshness budget |
| Conflict | Two current values for a single-valued property |
| Unresolved | Proposal older than 14 days |

The macOS Graph page shows nodes, edges, orphans and the review queue today.

## 8. Migration plan

| Step | Change | Reversible |
|---|---|---|
| M0 | Add the ontology document + zod schema in `kg-client`; no writes | Yes |
| M1 | Add `kgNodeRecord`/`kgEdgeRecord` tables (new prefix `kg_processlink_*`); no host tables touched | Yes, drop tables |
| M2 | Backfill sites, BUs, value streams and applications from the registry/catalogue (idempotent) | Yes, delete by `source = "backfill/1"` |
| M3 | Propose process/step nodes from an event log; human review queue only | Yes |
| M4 | Add `kgNodeId` to `signavio-map/1` node data and bind generated maps | Additive; default nil |
| M5 | Add `kgNodeId` to Advantage opportunities | Additive; nullable |
| M5b | Add `processlink_meeting` / `_block` tables and their node ids | Additive; new prefix |
| M6 | Enable GraphRAG retrieval behind `PROCESSLINK_GRAPHRAG` (off) | Yes |

Each step ships with a count check, a checksum over the migrated set, and a
dry-run output. No step runs without the previous one's audit.

## 9. Compatibility

- `teoa-process/1` is unchanged; maps still compile to the same ladder.
- `advantage-framework/1` is unchanged; KG ids are an optional reference.
- `process-catalog/1` entries gain an optional `kgNodeId`; existing entries
  stay valid.
- The KG's existing document types and conversions are untouched.
