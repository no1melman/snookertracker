---
status: planned
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
updated_at: 2026-10-12T15:13:40.476709Z
---

# Upgrade screens

## Overview
Presentation for selling the upgrade: the in-place offer (templates, pause), the generic offer screen for other paid features, and the benefits screen behind a menu item shown only while Free. Source: `docs/ddd-requirements.md` › Upgrade › `ShowUpgradeOffer`, `BenefitsScreen`. Scenarios S49, S50, S52, S53.

## Requirements
- [ ] `ShowUpgradeOffer(PaidFeature)` presentation: in place for templates and pause, the generic screen otherwise
- [ ] `BenefitsScreen`: the list of paid features in plain language, price (from the App Store, localised), Buy, Restore; shown only while free
- [ ] Benefits menu item on the hub: visible only while free; hidden on `AppUnlocked` and shown on `AppLocked`
- [ ] Buy → `PurchaseUnlock`; pending shows a waiting state; cancel and failure leave the screen unchanged
- [ ] Restore → `RestorePurchases`; "Nothing to restore" when none on record
- [ ] Follows the design language (022)

## Non-goals
- The guards that open the offer (edition-guard specs)

## Acceptance criteria
It must prevent: showing the offer on launch or as a repeated pop-up.

**Free limits** (verbatim, the benefits list must match): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

- Integration: benefits menu item hidden on `AppUnlocked` and shown on `AppLocked`; an unlock then revoke round trip deletes no match, player, template or series
- The offer never appears on launch or unprompted

**Implementation skills:** `ddd-cqrs` · **Tests:** `ddd-testing`
