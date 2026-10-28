# Live Flightdeck connections (UAT)

ProcessLink reads the **Flightdeck OS UAT API**, the **Vision** projection in
that OS, and the separate **Atlas** API. The connection is read-only: no OS,
Vision or Atlas record is created, promoted or changed by ProcessLink.

![Connections](shots/connections-light.png)

## What was verified live

Run on 2026-10-28 against the local UAT stack:

| Source | Endpoint | Verified answer |
|---|---|---|
| Flightdeck OS | `http://127.0.0.1:4173` | UAT quick-login enabled; signed in as `uat-admin` (admin); workspace `te-ops`; project `project-contract` |
| Advantage | `/api/apps/advantage/process-kpis`, `/opportunities` | 14 KPIs and 30 opportunities read; 44 graph facts written |
| Vision | `/api/project-vision`, `/api/vision/bootstrap` | projection `not_required`, strategy “HR AI rollout”, 4 roadmap items; owner view available to `uat-admin` |
| Atlas | `http://localhost:5173` | local UAT super-admin; 2 projects read; 3 graph facts written |

The live client test is in
`Tests/ProcessLinkKitTests/ProcessLinkKitTests.swift` and only runs when
`FLIGHTDECK_UAT_URL` is set. The `tools/uat-smoke.sh` script checks the same
endpoints with `curl` without printing a credential.

## UAT sign-in

Flightdeck OS exposes a deliberately narrow UAT shortcut:

1. `GET /api/auth/quick-login` returns `{ enabled, accounts: [{id,label,username}] }`.
   It never returns a password.
2. `POST /api/auth/quick-login {id}` runs the ordinary `verifyLogin` path and
   returns a `flightdeck_session` cookie.

ProcessLink shows the startable accounts (including `uat-admin`, the account
that can open Vision), posts only the opaque id, and stores the resulting
**session cookie in the macOS Keychain**. A password field is available for an
instance with quick login off; the password is used for one request and never
stored.

> UAT quick login is a launch-time convenience (`UAT_QUICK_LOGIN=true`), not a
> production identity. On a normal UAT/production instance use the ordinary
> account sign-in, or let the host's OIDC session supply the cookie.

## What is read

| Call | Purpose |
|---|---|
| `GET /api/auth/me` | principal, role |
| `GET /api/workspaces` | workspace membership |
| `GET /api/projects` + `X-Workspace-Id` | project context |
| `GET /api/project-vision` + `X-Project-Id` | Vision status, approved goals, required actions |
| `GET /api/vision/bootstrap` | strategy, roadmap, portfolio, benefits, decisions (owner view; optional) |
| `GET /api/apps/advantage/process-kpis` | 14 contract-process KPIs |
| `GET /api/apps/advantage/opportunities` | ranked improvement opportunities |
| `GET {atlas}/api/projects` | Atlas projects |

The OS session also uses `X-Workspace-Id` and `X-Project-Id`, the same
selection headers the OS console sends.

## Atlas identity

Atlas is a separate application. A **loopback Atlas** (the local UAT instance)
uses its development cookie `__sites_local_auth=1`; ProcessLink sends that
cookie only to `localhost`/`127.0.0.1`. A **hosted Atlas** sits behind its own
hosting dispatcher and needs a gateway sign-in token; set the optional token in
the Atlas card. Atlas SSO with Flightdeck is not implemented by Atlas yet, so
this is deliberately a UAT bridge, not production SSO.

Atlas's e-mail is kept out of the knowledge graph. The Atlas workspace node is
named “Atlas workspace”; only the local connection card shows the e-mail for
confirmation.

## What lands in the graph

| Source fact | Node kind | Stable id |
|---|---|---|
| OS workspace | business unit | `kg-os-workspace-<id>` |
| OS project | value stream | `kg-os-project-<workspace>-<project>` |
| Vision goal / roadmap | Hoshin objective | `kg-vision-goal-<slug>`, `kg-vision-roadmap-<id>` |
| Vision required action | action | `kg-vision-action-<slug>` |
| Vision benefit | savings record | `kg-vision-benefit-<id>` |
| Advantage KPI | metric | `kg-os-kpi-<project>-<id>` |
| Advantage opportunity | opportunity | `kg-os-opp-<project>-<id>` |
| Atlas project | initiative | `kg-atlas-project-<id>` |

Every node carries `source`, `sourceID`, confidence and `updatedAt`. Sync is
idempotent: the stable ids update the same node rather than appending a new
one. The graph page caps each overview column at seven shapes and shows the
real count in the header, so a live sync cannot turn the canvas into a stack.

## Security and privacy

- HTTPS is required everywhere except a loopback host. A URL with embedded
  credentials is refused.
- Only a session cookie is persisted, and only in the Keychain. Atlas tokens
  are optional and also Keychain-only.
- The service is read-only. It never sends a write to OS, Vision or Atlas.
- The audit log records `connection.sync` with the workspace/project and
  counts, never the cookie, token or e-mail.
- UAT data is still company data. The connection does not weaken the
  classification, group-size or PII rules; only aggregated OS/Vision facts are
  read.
- Session expiry returns a clear “sign in again” state.

## UI

**Trust → Connections** has a card for each source, the UAT account picker,
workspace/project selectors, Atlas URL/e-mail/token, one **Sync all** action,
last-sync time and sign-out. A snapshot run can connect without a hardcoded
credential:

```bash
APP_UAT_LOGIN=uat-admin APP_ATLAS_EMAIL=<atlas-local-email> \
APP_SNAPSHOT_PAGES=connections tools/snap.sh
```

`APP_SNAPSHOT_MINING` and the UAT variables are test seams; normal use is the
UI.

## Limits and next work

- **Atlas hosted identity** is not Flightdeck SSO; it needs the hosting
  gateway's token or a future Atlas service account.
- **Vision owner routes** are available only to an owner account. Other
  accounts get the shared projection, which is the intended permission shape.
- **No polling/webhooks.** Sync is explicit, so the audit log has one event per
  user action.
- **No writes back.** Promoting a live Advantage opportunity or creating a
  Vision benefit remains a human action in those apps.
- **Web form** does not yet have this page; when mounted as the TEOA sub-app it
  should use the same-origin session instead of a Keychain cookie.
- **KYP.ai** remains a separate connector; this page is OS/Vision/Atlas only.
