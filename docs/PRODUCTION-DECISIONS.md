# Production decisions still open

Date: 2026-10-30. These are owner/architecture decisions, not implementation
bugs. Each option lists what it changes and what it costs.

## 1. ProcessLink inside Flightdeck OS

Current: authenticated iframe at `/processlink/`, OS shell around it.

| Option | What changes | Cost |
|---|---|---|
| A. Keep iframe | none | Not an OS-owned route; two document contexts |
| B. Top-level redirect | OS ProcessLink nav opens `/processlink/` directly | Loses OS shell/navigation around the app |
| C. Micro-frontend | export ProcessLink as an OS-loaded module with a shared host contract | Build/runtime seam, versioning, shared styles |
| D. Merge into OS web | move ProcessLink pages into the OS Vite app | Largest change; release coupling |

Recommendation: **C** if the OS shell must remain; **B** only as an interim
full-screen mode. The iframe is the safe current state.

## 2. Native restore semantics

Backup currently exports summaries, not full relationship graphs.

| Option | Behavior |
|---|---|
| Merge | add records, match by id, keep existing |
| Replace | wipe and recreate from backup |
| New workspace | restore into a fresh store for review |

Recommendation: **new workspace/review**, then promote. Never silent replace.

## 3. Fleet scope

Current: local single-tenant control plane with per-device tokens.

Hosted fleet requires tenant isolation, admin identity, revocation audit,
deployment/backup, and an operator UI. Recommendation: keep local until a
hosted identity/tenant model is chosen.

## 4. PDF page-level annotations

ProcessLink anchors to map/process subjects, not PDF pages.

Options:
- add `page` to the annotation package when a PDF source is known;
- keep PDF Studio review-only and use map/process anchors.

Recommendation: keep review-only until a page anchor model exists.

## 5. Distribution

Without a **Developer ID Application** identity and notary credentials, the app
cannot be a Gatekeeper-trusted release. `tools/notarize.sh` is ready.

Required from owner:
- Developer ID Application certificate in the keychain
- Apple ID / team ID / app-specific password or notarytool profile
