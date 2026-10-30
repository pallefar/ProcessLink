# Local agent control-plane

Minimal enrollment/heartbeat service for the managed capture agent. It stores
device policy and consent references in `data/agents.json`; it does not receive
captures.

```sh
AGENT_ENROLL_TOKEN=change-me docker compose up -d processlink-agent
```

Endpoints (Bearer token):

- `POST /v1/enroll` — deviceID, policy, consents, workspace/project
- `POST /v1/heartbeat` — deviceID
- `GET /v1/policy?deviceID=…`
- `GET /health`

This is a local control plane, not a multi-tenant fleet service.
