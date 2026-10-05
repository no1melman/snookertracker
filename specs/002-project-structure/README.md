---
status: in-progress
created: 2026-10-05
priority: high
tags:
- cross-cutting
- infrastructure
parent: '1'
created_at: 2026-10-05T10:42:31.444768Z
updated_at: 2026-10-05T19:18:16.517579Z
transitions:
- status: in-progress
  at: 2026-10-05T19:18:16.517579Z
---

# Project structure & layering

## Overview
Set up the Swift module layout that every other spec builds into, and enforce the dependency rule at compile time. Source: `docs/ddd-requirements.md` › Cross-cutting › Layering, Context boundaries, Design-for-later constraints (ADR-0002, ADR-0003).

## Requirements
- [x] Swift package with separate modules per context (Matches, Players, Stats). Each context has a domain, application, infrastructure and presentation layer.
- [x] Domain modules are pure Swift (Foundation only) and sit at the root of the dependency chain: they depend on nothing, and application, infrastructure and presentation depend on them. No SwiftUI, SwiftData/Core Data, ActivityKit or UserNotifications in a domain module.
- [x] Contexts depend on each other only through published-event modules and open-host query protocols:
  - Players→Matches: customer/supplier
  - Matches→Players: OHS (`IsPlayerInLiveMatch`, `HavePlayedEachOther`)
  - Matches→Stats and Players→Stats: published language, conformist
  - Stats→Matches: OHS (`HeadToHead`, `AverageFrameTime`, `AverageMatchLength`)
- [ ] An iOS anti-corruption layer lives in infrastructure (adapters for UserNotifications, ActivityKit + App Intents, app lifecycle)
- [x] An in-process event dispatcher: after save, Stage 2 events reach their subscribers. Published event types are versioned.
- [x] An iOS app target that composes the modules (composition root)
- [ ] `swift build` and `swift test` run green in CI or locally

## Non-goals
- Any domain behaviour (covered by the context specs)
- Choosing the persistence engine beyond what the event store spec needs
- Full-state export (S24): the export spec

## Acceptance criteria
- Each domain target declares no dependencies in `Package.swift` and imports only Foundation (checked in review and by `/ddd conformance`; SwiftPM cannot forbid system frameworks)
- Matches cannot import Stats internals, only its OHS protocol module
- An empty test target passes for each module

**Implementation skill:** `ddd-project-structure`

## Progress
- **Done (2026-10-05 audit):**
  - `Package.swift` generates the Domain, Application, Infrastructure, Presentation and Published targets for each context, plus domain and integration test targets. Domain targets declare no dependencies, and every domain file imports only Foundation.
  - Cross-context visibility goes only through `*Published` modules (the `publishedDeps` table). Players → Matches is the customer/supplier adapter `PlayersForMatches` in `AppComposition`.
  - `EventDispatch` holds the dispatcher and the `PublishedEvent` protocol, whose `eventType` and `version` are versioned.
  - The `AppComposition` module is the composition root. The XcodeGen `project.yml` app target is a thin `@main` over it.
- **Decisions:** a shared `SQLiteSupport` module is the persistence engine for every context's infrastructure. Presentation depends only on Application (+ `DesignSystem`).
- **Remains:**
  - `iOSAdapters` is only a placeholder module. The real adapters come with specs 018–020.
  - The OHS protocols themselves don't exist yet (`StatsPublished` is empty). They arrive with 009 and 014.
  - A green `swift build` / `swift test` wasn't verified in this audit, and there is no CI config.
