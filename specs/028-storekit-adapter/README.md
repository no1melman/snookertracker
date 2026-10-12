---
status: complete
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
updated_at: 2026-10-12T16:09:09.116452Z
completed_at: 2026-10-12T16:09:09.116452Z
transitions:
- status: in-progress
  at: 2026-10-12T15:26:55.018370Z
- status: complete
  at: 2026-10-12T16:09:09.116452Z
---
# StoreKit adapter

## Overview
The App Store → Upgrade anti-corruption layer (ADR-0011): a StoreKit 2 implementation of `AppStorePort`, the only place StoreKit appears. Source: `docs/ddd-requirements.md` › Upgrade › Repository Port, Cross-cutting › Layering and Context boundaries. Scenarios S49, S50, S51.

## Requirements
- [x] `StoreKitAppStore: AppStorePort` in `ios/Sources/Upgrade/Infrastructure`:
  - `purchase(UnlockProductId) -> purchased | pending | cancelled | failed` (only verified transactions count as purchased)
  - `restore() -> unlockOnRecord: Bool` (sync, then current entitlements)
  - `transactionUpdates` (verified, revoked), listened to from launch, so Ask to Buy approvals arrive even after a restart
- [x] Composition root starts the listener at launch and feeds `HandleAppStoreUpdate`
- [x] Product price (localised) exposed for `BenefitsScreen`
- [x] StoreKit configuration file for local and test runs; product id set once
- [x] Layering: StoreKit appears only in Upgrade's infrastructure adapter (`AppStorePort`); the Matches, Players and Stats domains see only `CurrentEdition`, `AppUnlocked`, `AppLocked`

## Non-goals
- App Store Connect setup and server-side receipt validation

## Acceptance criteria
It must prevent: unlocking without a verified purchase; re-locking because the device is offline.

- StoreKitTest: purchase, Ask to Buy pending then approved, cancel, failure, restore with and without a purchase, refund/revocation → `AppLocked`
- Offline launch keeps the cached edition
- No `import StoreKit` outside the adapter (checked by build boundaries)

**Implementation skills:** `ddd-repositories`, `ddd-project-structure` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-12):**
  - `StoreKitAppStore` (`ios/Sources/Upgrade/Infrastructure/AppStore/StoreKitAppStore.swift`) is the only file that imports StoreKit. `AppContainer.makeAppStore()` returns it; `FakeAppStore` stays for tests and previews.
  - `transactionUpdates` listens to `Transaction.updates` from construction (launch) and checks `Transaction.currentEntitlements` / `Transaction.latest(for:)` once alongside. Verified transactions are finished; unverified ones are ignored.
  - `restore` = `AppStore.sync()` then current entitlements. `displayPrice` = `Product.displayPrice`.
  - `ios/StoreKit/SnookerTracker.storekit` (one family-shareable non-consumable, £2.99) is the app scheme's StoreKit configuration in `project.yml` and the tests' session file. Its product id is checked against `UnlockProductId.fullVersion`.
  - Tests:
    - SwiftPM `UpgradeStoreKitTests`: no StoreKit import outside the adapter (scans `Sources`, `App`, `LiveActivityWidget`), the configuration file matches the product id, the transaction-reading rule, and launch-vs-live ordering.
    - App-hosted `SnookerTrackerStoreKitTests` (xcodebuild, iOS simulator), 12 StoreKitTest cases: purchase, Ask to Buy pending then approved after a relaunch, cancel, failure, failed verification, restore with/without a purchase and offline, refund → `AppLocked`, launch with the purchase on record, offline launch keeps the cached edition, localised price.
- **Decisions:**
  - A launch that finds nothing on record reports nothing. Only a verified revocation locks, so an offline launch never re-locks.
  - The launch check is dropped if a live update was delivered first (`LaunchGate`), so a stale "verified" can't undo a refund.
  - If `AppStore.sync()` fails, an entitlement already on the device still restores; otherwise `AppStoreUnavailable`.
  - StoreKitTest needs an app host (`swift test` gets `SKServiceErrorDomain 2`), so that suite is an Xcode unit-test bundle.
  - StoreKitTest can't cancel a payment sheet with dialogs off (a simulated `userCancelled` surfaces as `.unknown` → failed), so the cancel case feeds StoreKit's own `.userCancelled` result to the adapter's translation.
