# Shared packages

The brief names eight packages. In this build they exist as modules with clear
seams, not as published npm packages — there is one consumer today (the web
form) and one mirrored implementation (the Swift kit). Extracting them into
workspace packages happens when the Flightdeck sub-app is wired in, because
that is when a second TypeScript consumer appears.

| Package in the brief | Where it lives now | Status |
|---|---|---|
| `process-model` | `macos/.../ProcessLinkKit/Domain.swift`, `web/src/domain/types.ts` | Defined; steps, variants, provenance, classification |
| `teoa-model` | `ProcessLinkKit/Domain.swift` (methods/waste/route), `web/src/domain/labels.ts` | Draft catalogue; must be replaced with official TE definitions (Q4) |
| `opportunity-engine` | `ProcessLinkKit/Scoring.swift`, `web/src/domain/rules.ts` | Implemented, tested in Swift, mirrored in TS |
| `privacy-guard` | `ProcessLinkKit/Privacy.swift`, `web/src/domain/rules.ts` | Implemented; policy evaluator + PII scan |
| `value-tracking` | `ProcessLinkKit/Scoring.swift` (ledger), `web/src/domain/rules.ts` | Implemented; estimate → commit → validate, conflict rule |
| `discovery-engine` | `macos/.../ProcessLinkKit/Mining.swift`, `web/src/pages/Mining.tsx` | Full event-log mining and task capture on macOS; web sample view |
| `kg-client` | `macos/.../Models.swift` (nodes/edges), `web/src/pages/Graph.tsx` | Local typed store + proposal model; real API is Phase 2 |
| `ai-core` | `ProcessLinkKit/Insights.swift`, `web/src/domain/ask.ts` | Local deterministic provider with citations; hosted provider is Phase 6 |

## Why not extract yet

1. **One consumer.** A package with one consumer is a folder with extra steps.
2. **The rules must be reviewable.** Privacy and savings logic is duplicated
   deliberately so a security reviewer can read each implementation without a
   build step; the shared golden behaviour is the test suite, not a transpiler.
3. **The host decides the seam.** Flightdeck's `capabilities`, `ai-core` and
   `diagram-schema` contracts determine the real package boundaries. Guessing
   them now would create a second integration surface to maintain.

Extraction plan: create `packages/{process-model,teoa-model,privacy-guard,
opportunity-engine,value-tracking}` with the TS sources moved verbatim, make
`web` depend on them through `pnpm` workspace links, then add a
`golden/*.json` fixture that both the Swift and TS suites read.
