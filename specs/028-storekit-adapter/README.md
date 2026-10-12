---
status: planned
created: 2026-10-12
priority: high
tags:
- upgrade
- ios
- storekit
depends_on:
- '23'
parent: '1'
created_at: 2026-10-12T15:13:40.472796Z
updated_at: 2026-10-12T15:13:40.472796Z
---

# StoreKit adapter

## Overview
The App Store → Upgrade anti-corruption layer (ADR-0011): a StoreKit 2 implementation of `AppStorePort`, the only place StoreKit appears. Source: `docs/ddd-requirements.md` › Upgrade › Repository Port, Cross-cutting › Layering and Context boundaries. Scenarios S49, S50, S51.

## Requirements
- [ ] `StoreKitAppStore: AppStorePort` in `ios/Sources/Upgrade/Infrastructure`:
  - `purchase(UnlockProductId) -> purchased | pending | cancelled | failed` (only verified transactions count as purchased)
  - `restore() -> unlockOnRecord: Bool` (sync, then current entitlements)
  - `transactionUpdates` (verified, revoked), listened to from launch, so Ask to Buy approvals arrive even after a restart
- [ ] Composition root starts the listener at launch and feeds `HandleAppStoreUpdate`
- [ ] Product price (localised) exposed for `BenefitsScreen`
- [ ] StoreKit configuration file for local and test runs; product id set once
- [ ] Layering: StoreKit appears only in Upgrade's infrastructure adapter (`AppStorePort`); the Matches, Players and Stats domains see only `CurrentEdition`, `AppUnlocked`, `AppLocked`

## Non-goals
- App Store Connect setup and server-side receipt validation

## Acceptance criteria
It must prevent: unlocking without a verified purchase; re-locking because the device is offline.

- StoreKitTest: purchase, Ask to Buy pending then approved, cancel, failure, restore with and without a purchase, refund/revocation → `AppLocked`
- Offline launch keeps the cached edition
- No `import StoreKit` outside the adapter (checked by build boundaries)

**Implementation skills:** `ddd-repositories`, `ddd-project-structure` · **Tests:** `ddd-testing`
