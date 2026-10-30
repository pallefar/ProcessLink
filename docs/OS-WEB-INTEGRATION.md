# OS and web-suite integration audit

Date: 2026-10-30. This is the wiring plan for the next batch; it is not a claim
that the integrations are already mounted.

## What exists

| Surface | Current state | Gap |
|---|---|---|
| ProcessLink web | Standalone Vite/React build; hash routes; feedback persisted in localStorage; host context from `?workspace=&project=`; OS suite page | Not yet mounted at an OS sub-app route; no shared OS store |
| Flightdeck OS | `ATLAS_URL`, inbound API, Maps/Advantage/Vision/contract-flow APIs | No ProcessLink sub-app manifest, route, or launch entry |
| Atlas | Repo running at `:5173`; OS context live; ProcessLink reads 2 projects | Atlas is not embedded in ProcessLink web; no shared deep link/state |
| Maps/DiagramForge | Maps API and contract-flow execution log imported natively | Web map is synthetic; no live map list, shape feedback or mine action |
| Vision | Projection read through OS session | No web Vision handoff; strategy/KPI sync is macOS-only |
| PDF Studio | Local document/signing app; separate server | No annotation or approved-document handoff into ProcessLink |
| DeckForge | Local deck desktop app | No initiative → brief/deck handoff |

**Batch 4 delivered the web half:** an OS suite page, host context, PDF Studio
annotation export, DeckForge brief export and web feedback persistence.

**Batch 5 delivered and verified the container and OS mount:** `docker-compose.yml`
for ProcessLink web, an OS `processlink` sub-app manifest, an iframe web module,
and local-compose switches that turn Advantage off and ProcessLink on.
The live UAT OS container was rebuilt on the new image; `/api/apps` now returns
`processlink` and no `advantage`, and ProcessLink web answers on `:4180`.
The previous OS container is retained as `flightdeck-presence-4173-pre-processlink`.

## Required route and session contract

1. Add a ProcessLink sub-app manifest to the OS and mount it under
   `/console/apps/processlink` with the OS shell and session cookie.
2. Pass `X-Workspace-Id` / `X-Project-Id` exactly as Maps/Advantage do; the web
   shell must not invent its own workspace selector.
3. Replace the standalone `dist` preview with an OS-hosted static bundle; keep
   the hash routes for deep links.
4. Add OS-side persistence for feedback, agent policy and automation handoff
   rather than browser memory.
5. Extend the OS app directory/9-dot entry so ProcessLink is discoverable next
   to Maps, Atlas, Vision, PDF Studio and DeckForge.

## Batch 4 wiring order

1. Mount ProcessLink web in the OS with host context.
2. Live Maps/DiagramForge: map list, shape feedback and “Mine this map”.
3. Atlas/Vision deep links and KPI/strategic-bet handoff.
4. PDF Studio annotation/approved-document handoff.
5. DeckForge brief/deck handoff from an initiative.

Each step needs a route-level test and a screenshot before the next.
