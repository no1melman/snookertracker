---
status: planned
created: 2026-10-12
priority: high
tags:
- upgrade
- edition
depends_on:
- '2'
parent: '1'
created_at: 2026-10-12T15:13:33.090443Z
updated_at: 2026-10-12T15:13:33.090443Z
---

# Upgrade core: Edition

## Overview
The new **Upgrade** context (generic) and its `Edition` aggregate: domain, local store, published events, use cases against an `AppStorePort` (faked here) and the `CurrentEdition` open host. Every edition guard in Matches, Players and Stats reads from it. Source: `docs/ddd-requirements.md` › Context: Upgrade › Edition and the Changes section (ADR-0010, ADR-0011). Scenarios S49–S53.

New module `ios/Sources/Upgrade` (domain, application, infrastructure, presentation), following 002.

## Requirements
- [ ] Value objects:
  - `EditionStatus`: `free` (initial) | `unlocked`; free → unlocked, unlocked → free, no other
  - `FreeLimits`: live matches 1; active players 5; visible ended matches 10; allowed styles {most frames wins}; allowed break rules {alternate}; one table, owned here (ADR-0011)
  - `PaidFeature`: templates, manualPause, raceTo, sets, winnerBreaks, extraPlayers, fullHistory, colours, headToHead, stats, series, severalLiveMatches, lockScreen
  - `UnlockProductId`: the single non-consumable product identifier
- [ ] `Edition.initial` (free); `unlock()` (idempotent when unlocked, raises `AppUnlocked`); `lock()` (idempotent when free, raises `AppLocked`); `allows(PaidFeature)`; `limits` (nil when unlocked)
- [ ] Invariant: the status changes only through `unlock` and `lock`, never because a check failed or the device is offline
- [ ] `AppUnlocked`, `AppLocked` published as Stage 2 (Upgrade's published language, versioned shape)
- [ ] Ports: `EditionStore` (`get`, `save`; single per device, cached locally, survives offline launches) with a SQLite adapter; `AppStorePort` (`purchase`, `restore`, `transactionUpdates`) with a fake only (the StoreKit adapter is a separate spec)
- [ ] Use cases: `PurchaseUnlock` (purchased → unlock; pending → nothing yet; cancelled or failed → nothing changes), `RestorePurchases` ("Nothing to restore" when none on record), `HandleAppStoreUpdate` (verified → unlock, revocation → lock), `ShowUpgradeOffer(PaidFeature)` (in place for templates and pause, the generic screen otherwise; raises nothing)
- [ ] Read: `CurrentEdition` open host (status, `FreeLimits` when free, `allows`), served from `EditionStore`, never waits on the App Store
- [ ] Composition root builds Upgrade before Matches, Players and Stats and hands each `CurrentEdition` plus the event subscription

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
