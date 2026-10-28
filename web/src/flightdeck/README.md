# Shipping ProcessLink inside Flightdeck

ProcessLink is designed as a **sub-app**, not host code: its own tables, its
own kill switch, a per-workspace install row, and a replaceable nav entry.
This folder is the adapter, not a second implementation.

## What replaces what

| Today | After |
|---|---|
| `advantage` sub-app: framework, A3, boards, X-matrix, opportunities, benefit observation | ProcessLink keeps those tables readable and adds the KYP.ai source, the map binding and the savings lifecycle. |
| `advantage` nav entry | `processlink` nav entry under **Ops & insight**. |
| Advantage opportunities computed on read from contracts + maps | Same shape, plus KYP.ai source; `impact ÷ effort` preserved. |

**Do not delete `advantage` in the first release.** Install both, feature-flag
the new nav entry, and read Advantage's tables for the existing TEOA records
(see `docs/KG-ONTOLOGY.md` M5). Dual-run for one quarter; then retire the old
surface with a data migration that keeps ids.

## Install

1. Copy `src/` into `flightdeck/web/src/subapps/processlink/` and add a
   `mainProcessLink.tsx` entry, mirroring `mainAdvantage.tsx`.
2. Register `processLinkManifest` in `flightdeck/server/subapps/registry.ts`
   beside `advantageManifest`.
3. Add `server/subapps/processlink/manifest.ts` with `capabilities: []` and
   the same route prefix; add `applyProcessLinkSchema` with the new tables
   (`processlink_*`, generated into `db/migrations/`, never hand-edited).
4. Add the kill switch `SUBAPP_PROCESSLINK_ENABLED` (default **off**) and a
   `subapps.lock.json` entry via `npm run subapps:lock`.
5. Add a `subapp_processlink_install` row and a consent screen that states
   the purpose limitation and the group threshold.
6. Add the nav entry and a redirect from the retired `advantage` route behind
   a flag, so links do not break.

## Host contracts ProcessLink relies on

- **Session**: workspace id, user, roles, region, policy thresholds.
- **Permissions**: node/edge ACL inheritance; ProcessLink adds none.
- **AI gateway**: `ai-core` provider selection, classification gate, cost
  metering. The web must never hold a provider key.
- **Maps**: `signavio-map/1` with an added `kgNodeId` on node data.
- **DeckForge**: deck schema + template library.
- **Audit**: the host's immutable audit sink.

## Routes (server sketch)

```
GET  /api/apps/processlink/processes
GET  /api/apps/processlink/opportunities
POST /api/apps/processlink/opportunities/:id/promote
POST /api/apps/processlink/initiatives/:id/commit
POST /api/apps/processlink/initiatives/:id/validate
POST /api/apps/processlink/sync
POST /api/apps/processlink/ask
GET  /api/apps/processlink/kg/nodes
POST /api/apps/processlink/kg/reviews
GET  /api/apps/processlink/audit
```

Every write re-runs the privacy guard server-side; a client that skips the
guard still cannot write. The audit appends one event per decision.

## Data migration sketch

```sql
-- additive only; no advantage table is renamed
ALTER TABLE subapp_advantage_items ADD COLUMN kg_node_id TEXT;
ALTER TABLE subapp_advantage_focus ADD COLUMN kg_node_id TEXT;
CREATE TABLE processlink_sync_run (...);
CREATE TABLE processlink_opportunity (...);
CREATE TABLE processlink_initiative (...);
CREATE TABLE processlink_savings (...);
CREATE TABLE processlink_kg_proposal (...);
```

`ALTER TABLE ... ADD COLUMN` is safe on both SQLite and Postgres. The full
migration is generated, not hand-written, per the host's `gen_pg_schema.py`
ritual.

## What must be true before this ships

- DPIA + works-council sign-off for each country.
- Real KYP.ai sandbox contract tests (Q1/Q2).
- KG migration approved (Q5).
- Feature flag off by default; rollback is removing the nav entry, not a
  data rollback.
