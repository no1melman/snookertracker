---
status: planned
created: 2026-10-05
priority: medium
tags:
- players
depends_on:
- '11'
parent: '1'
created_at: 2026-10-05T10:42:31.491833Z
updated_at: 2026-10-05T10:42:31.491833Z
---

# Me setting & welcome

## Overview
Which player is "Me" on this device, and the first-launch welcome. Source: `docs/ddd-requirements.md` › Players › MeSetting. Scenarios S18, S19, S33, S38, S42, S45, S48.

## Requirements
- [ ] `Me`: an optional `PlayerId`. `set` and `clear` raise nothing.
- [ ] A `MeSettingStore` port and adapter (one per device)
- [ ] `SetMe`: from the welcome, the main menu or settings
- [ ] `UpdateMeOnMerge`: policy on `PlayersMerged`; Me follows the kept player
- [ ] `ClearMeOnRemoval`: policy on `PlayerRemoved`
- [ ] `WhoAmI` read model: id and name, displayed "Me (Callum)". Published to Stats.
- [ ] `Welcome` on first launch: name entry (creates the player and sets Me), then a skippable, replayable walkthrough

## UI (design language: 022)
- [ ] **Welcome:** a full-screen name entry on first launch, then a skippable walkthrough, which can be replayed from Settings
- [ ] Me is shown as "Me (Callum)" on the hub and in Settings, and can be set or changed from either (`SetMe`)

## Non-goals
- Multiple Me identities

## Acceptance criteria
- Integration tests: set, follow on merge, clear on removal; the welcome creates the player and sets Me

**Implementation skills:** `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`
