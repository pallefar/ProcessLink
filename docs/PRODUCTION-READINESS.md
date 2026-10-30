# Production readiness

Date: 2026-10-30. This matrix distinguishes demo/UAT readiness from production.

| Area | Status | Evidence / blocker |
|---|---|---|
| OS identity | Ready | `/processlink/` proxy requires the OS session; 401 unauthenticated, 200 authenticated |
| Direct web exposure | Closed | ProcessLink web has no host port; only the shared Docker network |
| OS-backed state | Ready | `/api/processlink/state`; feedback load verified through the API |
| Agent device tokens | Ready | Per-device tokens; wrong token 401; list/revoke tested |
| Fleet administration | Partial | Local single-tenant control plane; no hosted multi-tenant service |
| Update integrity | Partial | SHA-256 and bundle signature checked; **not notarized** |
| Developer ID signing | Blocked | No Developer ID Application identity in this environment |
| PDF Studio inbox | Ready | PDF Studio File → ProcessLink inbox; writes `.ack` |
| PDF page annotations | Not done | ProcessLink anchors are process/map subjects, not PDF pages |
| DeckForge round-trip | Ready | create + update verified at revision 2 |
| OS sub-app route | Partial | Authenticated iframe at `/processlink/`, not an OS-owned React route |
| Native restore | Not done | Backup inspection only; no restore |
| Data store | Partial | SwiftData native + OS JSON web state; not a shared multi-user DB |

## Notarization

Run with the owner's Developer ID and notary credentials:

```sh
DEVELOPER_ID="Developer ID Application: …" TEAM_ID=… \
APPLE_ID=… APP_PASSWORD=… tools/notarize.sh
```

or set `NOTARY_PROFILE`.

Without that identity, the app can be signed with Apple Development but Gatekeeper
will not treat it as a distributed release.
