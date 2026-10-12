---
status: complete
created: 2026-10-12
priority: high
tags:
- upgrade
- edition
depends_on:
- '2'
parent: '1'
created_at: 2026-10-12T15:13:33.090443Z
updated_at: 2026-10-12T15:24:57.149029Z
completed_at: 2026-10-12T15:24:57.149029Z
transitions:
- status: in-progress
  at: 2026-10-12T15:18:36.433972Z
- status: complete
  at: 2026-10-12T15:24:57.149029Z
---
# Upgrade core: Edition

## Overview
The new **Upgrade** context (generic) and its `Edition` aggregate: domain, local store, published events, use cases against an `AppStorePort` (faked here) and the `CurrentEdition` open host. Every edition guard in Matches, Players and Stats reads from it. Source: `docs/ddd-requirements.md` › Context: Upgrade › Edition and the Changes section (ADR-0010, ADR-0011). Scenarios S49–S53.

New module `ios/Sources/Upgrade` (domain, application, infrastructure, presentation), following 002.

## Requirements
- [x] Value objects:
  - `EditionStatus`: `free` (initial) | `unlocked`; free → unlocked, unlocked → free, no other
  - `FreeLimits`: live matches 1; active players 5; visible ended matches 10; allowed styles {most frames wins}; allowed break rules {alternate}; one table, owned here (ADR-0011)
  - `PaidFeature`: templates, manualPause, raceTo, sets, winnerBreaks, extraPlayers, fullHistory, colours, headToHead, stats, series, severalLiveMatches, lockScreen
  - `UnlockProductId`: the single non-consumable product identifier
- [x] `Edition.initial` (free); `unlock()` (idempotent when unlocked, raises `AppUnlocked`); `lock()` (idempotent when free, raises `AppLocked`); `allows(PaidFeature)`; `limits` (nil when unlocked)
- [x] Invariant: the status changes only through `unlock` and `lock`, never because a check failed or the device is offline
- [x] `AppUnlocked`, `AppLocked` published as Stage 2 (Upgrade's published language, versioned shape)
- [x] Ports: `EditionStore` (`get`, `save`; single per device, cached locally, survives offline launches) with a SQLite adapter; `AppStorePort` (`purchase`, `restore`, `transactionUpdates`) with a fake only (the StoreKit adapter is a separate spec)
- [x] Use cases: `PurchaseUnlock` (purchased → unlock; pending → nothing yet; cancelled or failed → nothing changes), `RestorePurchases` ("Nothing to restore" when none on record), `HandleAppStoreUpdate` (verified → unlock, revocation → lock), `ShowUpgradeOffer(PaidFeature)` (in place for templates and pause, the generic screen otherwise; raises nothing)
- [x] Read: `CurrentEdition` open host (status, `FreeLimits` when free, `allows`), served from `EditionStore`, never waits on the App Store
- [x] Composition root builds Upgrade before Matches, Players and Stats and hands each `CurrentEdition` plus the event subscription

## Non-goals
- The StoreKit adapter and ACL (separate spec)
- Any guard inside Matches, Players or Stats (one spec each)
- Offer, benefits and menu-item UI (separate spec)

## Acceptance criteria
**Free limits** (verbatim): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

It must prevent: unlocking without a verified purchase; re-locking because the device is offline; showing the offer on launch or as a repeated pop-up; deleting or rewriting any other context's data.

- Domain unit: `EditionStatus` transitions allowed and refused; `unlock` and `lock` idempotency; `allows` for every `PaidFeature` in both editions; `FreeLimits` values
- Integration (fake `AppStorePort`): purchase purchased, pending then approved later (including after a restart), cancelled and failed; restore with and without a purchase on record; revocation → `AppLocked`; offline launch keeps the cached edition

**Implementation skills:** `ddd-tactical-patterns`, `ddd-repositories`, `ddd-application-layer`, `ddd-domain-events`, `ddd-cqrs`, `ddd-project-structure` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-12):**
  - New `Upgrade` context in `ios/Sources/Upgrade` (Domain, Application, Infrastructure, Presentation, Published), first in `Package.swift`. Matches, Players and Stats list `Upgrade` in their published deps; Upgrade depends on no other context.
  - Domain: `Edition` (`initial`, `reconstitute`, `unlock(at:)`, `lock(at:)`, `allows`, `limits`), `EditionStatus`, `FreeLimits.standard`, `PaidFeature` (with `offerPlacement`), `MatchStyleKind`, `BreakRuleKind`, `UnlockProductId`, events `AppUnlocked` / `AppLocked`.
  - Published: `CurrentEdition`, `FixedEdition` (test double and default), `AppUnlockedPublished` / `AppLockedPublished` (v1), `UpgradeOfferRequest`, `ShowUpgradeOfferAction`, `UpgradeRequired`.
  - Application: `EditionStore` and `AppStorePort` ports (with `displayPrice` for the benefits screen), `UpgradeUseCases` (PurchaseUnlock, RestorePurchases, HandleAppStoreUpdate, listener), `ShowUpgradeOffer`, `StoredEdition` (the open host).
  - Infrastructure: `SQLiteEditionStore` (single `edition` row; no row = Free) and `FakeAppStore`.
  - Composition root builds Upgrade first and hands `edition` to `PlayersService`, `MatchUseCases`, `MatchSettingsService`, `TemplateUseCases`, `MatchRecordsProjection`, `SeriesUseCases`, and to the `PlayersPorts`, `MatchesPorts`, `StatsPorts`, `SeriesPorts` (with `showUpgradeOffer`). No guards yet.
  - Tests: domain (`EditionTests`) and integration (`UpgradeIntegrationTests`) cover every acceptance item.
- **Decisions:**
  - The value objects live in `UpgradeDomain`; `UpgradePublished` re-exposes them as typealiases, so the Free-limits table exists once and downstream imports only `UpgradePublished`.
  - Upgrade names styles and break rules in its own words (`MatchStyleKind`, `BreakRuleKind`); Matches maps onto them.
  - Published events follow the codebase convention: `AppUnlockedPublished` / `AppLockedPublished` (`Upgrade.AppUnlocked`, `Upgrade.AppLocked`).
  - `StoredEdition` reads the store once at launch and is written through on every save, so `CurrentEdition` is synchronous and never waits on the App Store.
  - `restore()` throws `AppStoreUnavailable` when offline, and `RestorePurchases` returns `.appStoreUnavailable` (S50 "Couldn't reach the App Store").
  - Every `edition` parameter defaults to `FixedEdition.unlocked`, so existing tests keep their behaviour.
  - The App Store seam is `AppContainer.makeAppStore()`. Spec 028 swaps in StoreKit there.
- **Remains:**
  - The StoreKit adapter (spec 028), the guards in each context, and the offer and benefits UI. `UpgradeOfferRouter` and `UpgradePorts` are ready for that UI.
  - The benefits-menu and no-data-loss round-trip integration tests listed in the requirements belong to the UI and guard specs.
