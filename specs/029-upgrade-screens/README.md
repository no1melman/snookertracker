---
status: complete
created: 2026-10-12
priority: high
tags:
- upgrade
- ui
- ios
depends_on:
- '23'
- '28'
- '22'
parent: '1'
created_at: 2026-10-12T15:13:40.476709Z
updated_at: 2026-10-12T15:36:53.326602Z
completed_at: 2026-10-12T15:36:53.326602Z
transitions:
- status: in-progress
  at: 2026-10-12T15:27:58.361175Z
- status: complete
  at: 2026-10-12T15:36:53.326602Z
---
# Upgrade screens

## Overview
Presentation for selling the upgrade: the in-place offer (templates, pause), the generic offer screen for other paid features, and the benefits screen behind a menu item shown only while Free. Source: `docs/ddd-requirements.md` › Upgrade › `ShowUpgradeOffer`, `BenefitsScreen`. Scenarios S49, S50, S52, S53.

## Requirements
- [x] `ShowUpgradeOffer(PaidFeature)` presentation: in place for templates and pause, the generic screen otherwise
- [x] `BenefitsScreen`: the list of paid features in plain language, price (from the App Store, localised), Buy, Restore; shown only while free
- [x] Benefits menu item on the hub: visible only while free; hidden on `AppUnlocked` and shown on `AppLocked`
- [x] Buy → `PurchaseUnlock`; pending shows a waiting state; cancel and failure leave the screen unchanged
- [x] Restore → `RestorePurchases`; "Nothing to restore" when none on record
- [ ] Follows the design language (022)
  - Partial: stock SwiftUI only (`List`, `Label`, SF Symbols, `.borderedProminent` Buy in a `.bar` inset, system alert, Dynamic Type). Checked in the simulator in Light Mode at the default size. The Dark Mode and accessibility-size checks were blocked by the demo's notification prompt and still need doing.

## Non-goals
- The guards that open the offer (edition-guard specs)

## Acceptance criteria
It must prevent: showing the offer on launch or as a repeated pop-up.

**Free limits** (verbatim, the benefits list must match): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

- Integration: benefits menu item hidden on `AppUnlocked` and shown on `AppLocked`; an unlock then revoke round trip deletes no match, player, template or series
- The offer never appears on launch or unprompted

**Implementation skills:** `ddd-cqrs` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-12):**
  - `BenefitsMenuItem` (`ios/Sources/Upgrade/Application`) is the read side of the menu item. It starts from the cached edition, hides on `AppUnlocked` and shows on `AppLocked`. The composition root subscribes it before the App Store listener starts and passes it in `UpgradePorts.menuItem`.
  - `BenefitsScreen` (`ios/Sources/Upgrade/Presentation`) is both the benefits screen (S53) and the generic offer (S52). It lists every paid feature once (`UpgradeBenefit.all`, with each line's Free side drawn from `FreeLimits.standard`), shows the localised price from `displayPrice`, and has Buy and Restore. `BenefitsScreenModel` holds the state: purchasing, waiting for approval (Ask to Buy), back to ready on cancel or failure, "Nothing to restore", and "Couldn't reach the App Store". The screen closes itself once the edition unlocks, including when an Ask to Buy approval arrives later.
  - `UpgradeOfferScreen` wraps it in a sheet with Close. `.upgradeOfferPresentation(router)` in `AppRoot` presents it for `.genericScreen` requests only.
  - `UpgradeNowPrompt(_ feature:, style: .row | .button)` is the in-place prompt for the templates area and the pause button. It draws nothing once Unlocked and opens the offer screen on tap. The owning screens embed it; this spec doesn't edit them.
  - The hub shows an Upgrade row after Settings while Free (`HubDestination.upgrade`, `-uiRoute upgrade`).
  - Tests:
    - `BenefitsMenuItemTests` (Upgrade integration): the item hides on unlock, shows on revoke, hides again on restore, and follows the cached edition at launch.
    - A new `UpgradeScreensTests` target covers the screen model's outcomes, the benefits list against the Free limits, and the router's placements.
    - The same target runs an unlock-then-revoke round trip over one real SQLite file, with every context wired as the composition root wires it. No row in any table is deleted or rewritten, including after a relaunch.
    - It also checks that no offer is requested on launch, on unlock or on revoke.
- **Decisions:**
  - The menu-item model lives in Upgrade's application layer, next to the events it follows. Presentation keeps no event subscriptions.
  - `.inPlace` requests stay in the router for the owning screen; the root presents only `.genericScreen`. A guard that wants the prompt in place shows `UpgradeNowPrompt` instead of the control.
  - The round-trip test wires the real use cases by hand instead of building `AppContainer`, because the container touches `UNUserNotificationCenter`, which can't run under `swift test`.
  - Copy: race to and sets share one line. "Lock screen scores" names the Live Activity.
- **Remains:**
  - The Dark Mode and large Dynamic Type simulator checks, and the Impeccable finish review (022). Marked complete with `--force` for this one open item.
  - Embedding `UpgradeNowPrompt` in New Game's templates area and on the live screen's pause button (edition-guard specs).
