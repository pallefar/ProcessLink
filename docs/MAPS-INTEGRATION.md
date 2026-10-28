# Flightdeck Maps integration

ProcessLink does not draw a private picture. It reads and writes **real
`signavio-map/1` documents**, and Flightdeck Maps renders the same document.
The integration is two-way because both sides read the one document.

## 1. The document is the integration

```
signavio-map/1
  id, label
  nodes[]  { id, type, label, position, data }
  edges[]  { id, source, target, label? }
  meta     { createdBy, approved, sourceProcessId, lanes, ... }
```

ProcessLink adds two **optional, additive** fields (patch in
`project-contract/flightdeck/server/subapps/maps/lib/model.ts`):

| Field | Where | Owner | Meaning |
|---|---|---|---|
| `data.processLink` | per shape | ProcessLink | binding to a KG step + a read-only snapshot of mined facts |
| `meta.processLink` | per map | ProcessLink | process / KG process, generated-at, source, initiative |

Because both are optional, every map written before this change is still
valid, and every map written by Maps alone still compiles to `teoa-process/1`
unchanged.

```jsonc
// node.data.processLink
{
  "processId": "p-order-intake",
  "stepId": "step-p-order-intake-1",
  "kgNodeId": "kg-step-p-order-intake-1",
  "kgProcessId": "kg-proc-p-order-intake",
  "syncedAt": "2026-10-28T09:00:00Z",
  "metrics": { "minutes": 9, "handoffs": 1, "rework": 0.18, "evidence": 398, "waste": "Rework" },
  "topOpportunity": { "id": "opp-pricing-check", "title": "Remove the duplicate pricing check…", "hours": 410, "route": "simplify" },
  "savingHours": 540
}
```

## 2. Two-way behaviour

| Direction | What moves | Where it is enforced |
|---|---|---|
| ProcessLink → Maps | generated as-is map, node bindings, metrics snapshot, opportunity/saving badges | `MapsBridge.makeMap` writes the document; `registerMap` creates the map KG node and `documented_in` edge |
| Maps → ProcessLink | label, role/lane, system, timing, added/removed shapes, map approval state | `MapsBridge.loadAll` / `updateNode`; the shape inspector shows drift and ProcessLink context |
| Map edit → graph | a proposal, never a silent overwrite | `recordMapEdit` writes the map node note + audit; the step node is untouched |
| ProcessLink → map edit | "Restore from discovery" on a drifted shape | `MapsBridge.updateNode` with mined values, audited |
| Map publish | document save + map node confidence/notes | file save or `PUT /api/apps/maps/maps/:id` with `If-Match` in the host |

**Ownership rule.** Maps owns the shape (label, role, system, timing, layout).
ProcessLink owns the mined facts and the work (step, metrics, opportunity,
initiative, saving). Neither silently writes the other's fields.

## 3. Flightdeck host wiring

The map schema and panel are patched in the host:

- `server/subapps/maps/lib/model.ts` — `ProcessLinkNodeSchema`, `data.processLink`, `meta.processLink`.
- `web/src/subapps/maps/ProcessLinkPanel.tsx` — read-only panel mounted at the end of `NodeInspector`.
- `web/src/subapps/maps/Editor.tsx` — one import and one render.

The panel reads `node.data.processLink` (the snapshot), so it costs no request
per selection and works offline. It links to
`processlink://step/<kgNodeId>`; the ProcessLink app registers that scheme.

### Routes ProcessLink uses in the host

| Method | Route | Purpose |
|---|---|---|
| `GET` | `/api/apps/maps/maps/:id` | read the document + ETag |
| `PUT` | `/api/apps/maps/maps/:id` | publish a generated/updated map (send `If-Match`) |
| `POST` | `/api/apps/maps/maps` | create a map |
| `GET` | `/api/apps/maps/maps/:id/releases` | compare a published version |
| `POST` | `/api/apps/maps/maps/:id/comments` | a review note on a shape (next pass) |

ProcessLink does **not** write the host tables directly. It goes through the
Maps API, so approvals, history, ETag conflict handling and the kill switch
still apply. The host remains the source of truth for the document.

### Optional live route (Phase 3)

For fresh metrics without waiting for a sync, add:

```
GET /api/apps/processlink/shape/:kgNodeId
→ { metrics, opportunities[], initiative, saving, provenance }
```

The panel can hydrate from this after rendering the snapshot; the snapshot
stays as the offline fallback and the citation target.

## 4. Drift and conflict rules

| Situation | Reading | Action |
|---|---|---|
| map role ≠ mined role | map reflects a local variation | "Map proposal" card; save writes an audited proposal; human chooses |
| map system ≠ mined application | application ownership changed | same |
| map time ≠ mined minutes | estimate vs observation | same; no automatic overwrite |
| map has a shape with no binding | human-added step | "Bind to a step" menu; stays unbound until a human binds it |
| mined step missing from map | map is incomplete | map badge shows `n of m bound`; "Regenerate" creates a fresh map, never edits the human one |
| map `updatedAt` > `syncedAt` | map newer than evidence | drift badge; ProcessLink offers "Restore" or "Keep proposal" |

No drift is silently resolved. `recordMapEdit` writes an audit event and a
note on the map's KG node; the step node is unchanged until a human promotes
the standard-work change.

## 5. State in this build

**Implemented**
- macOS Maps workspace imports **every map in every enabled Flightdeck Maps
  project** through `GET /api/apps/maps/maps` and
  `GET /api/apps/maps/maps/:id` on open/sync. Maps are deduplicated by id and
  written to `APP_MAPS_DIR`; an existing local document is kept so a local
  edit is never overwritten by a re-import.
- It reads/writes `signavio-map/1` from `APP_MAPS_DIR` (default Application
  Support), seeds two local as-is maps, binds shapes,
  shows live ProcessLink metrics/opportunities/savings in the shape inspector,
  detects drift, restores from discovery, creates a map KG node, and audits
  edits.
- Flightdeck schema extension + `ProcessLinkPanel` mounted in the real
  `NodeInspector`.
- Map checks are included in the 73 in-app checks: document schema, bindings,
  drift, persistence, graph node and edge, plus live import.

**Not yet**
- Live host connection (no Flightdeck server in this session); the folder
  bridge is the stand-in.
- Approval/release round-trip (`PUT` with `If-Match`) — the host route exists,
  the client is next.
- Shape-level comments from ProcessLink.
- Web form uses its own generated map view; it will read the same documents
  once the sub-app is mounted.

## 6. Migration

1. Ship the additive schema + panel. No data change; old maps unchanged.
2. ProcessLink publishes its first generated map through `POST /maps` with
   `meta.processLink`. Human maps keep working without it.
3. For an existing map, ProcessLink binds shapes one at a time (reviewed) and
   writes `data.processLink`; never bulk-overwrites.
4. Enable live hydration behind `PROCESSLINK_MAPS_LIVE` (off by default).
