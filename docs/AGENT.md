# Managed capture agent

The agent is a **local policy**, not a fleet service.

- `CapturePolicyRecord` stores the interval, maximum session length, consent
  version and which content signals are enabled.
- `ConsentRecord` is per site/role/version, with an agreement reference and
  optional expiry. No person is named.
- The scheduler starts a session when the policy is active, consent is valid and
  the interval has elapsed. It stops at the maximum session length and saves the
  normal local capture aggregate.
- `CaptureTaskRecord` stores task segments derived from app/window changes.
  **AI name tasks** can replace app-level labels with a process vocabulary using
  the local transformers.js sidecar.

The current implementation is single-Mac. A fleet agent needs enrolment,
central policy distribution, revocation, and a DPIA/works-council agreement.

## Enrollment exchange

The policy export includes a generated device id, endpoint, workspace/project
and active consents. **Import policy** applies policy fields only; consent is
not imported and must be granted locally. **Heartbeat** records liveness locally.
There is still no fleet server.

## Local control plane

`agent/server.mjs` (Docker service `processlink-agent`, port 4185) provides
enroll, heartbeat and policy retrieval with a bearer enrollment token. It
stores only device policy/consent references; captures never leave the Mac.
The native agent card can enroll, heartbeat and fetch policy from this service; the enrollment token is stored in the Keychain. This is a local control plane, not a multi-tenant fleet service.
