# ProcessLink web in Docker + OS mount

## 1. Build and run ProcessLink web

```sh
cd ProcessLink
npm --prefix web run build
docker compose up -d --build
```

The container is `processlink-web`, published on `127.0.0.1:4180`, with a
`/healthz` endpoint. Set `PROCESSLINK_PORT` to publish a different port.

The image serves the built `web/dist` bundle; build the web app first. The
multi-stage npm build is intentionally not in the Dockerfile because this
machine's registry TLS is behind a corporate proxy.

## 2. OS source mount

The OS worktree (`/Users/te451223/FlightDeck OS/wt-integration/flightdeck`)
contains:

- `server/subapps/processlink/manifest.ts` — a no-table, no-capability sub-app
- `web/src/subapps/processlink/index.tsx` — full-bleed iframe to
  `VITE_PROCESSLINK_URL` (default `http://127.0.0.1:4180`)
- `deploy/macos-local/docker-compose.local.yml`:
  - `SUBAPP_ADVANTAGE_ENABLED: "false"`
  - `SUBAPP_PROCESSLINK_ENABLED: "true"`
  - `SUBAPPS_DEFAULT_ON` includes `processlink`

This makes ProcessLink the Ops & insight nav entry; Advantage remains installed
and can be re-enabled by restoring its kill switch.

## 3. Rebuild the OS

```sh
cd "/Users/te451223/FlightDeck OS/wt-integration"
docker compose -f deploy/macos-local/docker-compose.local.yml build flightdeck
docker compose -f deploy/macos-local/docker-compose.local.yml up -d flightdeck
```

Then open `http://127.0.0.1:4173/console/apps/processlink`.

Verified 2026-10-30: the live UAT container was recreated from
`flightdeck-presence:processlink-test`; `/api/apps` returned `processlink` and
no `advantage`. The previous container is stopped and retained as
`flightdeck-presence-4173-pre-processlink` for rollback.

For a non-local deployment, build the OS web with
`VITE_PROCESSLINK_URL=https://processlink.example.com` and publish ProcessLink
behind the same trusted proxy. The iframe is not authenticated by itself; OS
access control must protect the ProcessLink origin.

## Rollback

Set `SUBAPP_ADVANTAGE_ENABLED=true`, remove `processlink` from
`SUBAPPS_DEFAULT_ON`, rebuild/restart. The Advantage manifest, routes and data
were not removed.
