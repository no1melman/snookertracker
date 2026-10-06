---
status: in-progress
created: 2026-10-05
priority: medium
tags:
- players
depends_on:
- '11'
parent: '1'
created_at: 2026-10-05T10:42:31.491833Z
updated_at: 2026-10-05T20:51:19.903135Z
transitions:
- status: in-progress
  at: 2026-10-05T20:51:19.903135Z
---

# Me setting & welcome

## Overview
Which player is "Me" on this device, and the first-launch welcome. Source: `docs/ddd-requirements.md` › Players › MeSetting. Scenarios S18, S19, S33, S38, S42, S45, S48.

## Requirements
- [x] `Me`: an optional `PlayerId`. `set` and `clear` raise nothing.
- [x] A `MeSettingStore` port and adapter (one per device)
- [x] `SetMe`: from the welcome, the main menu or settings
- [x] `UpdateMeOnMerge`: policy on `PlayersMerged`; Me follows the kept player
- [x] `ClearMeOnRemoval`: policy on `PlayerRemoved`
  - Both are `MePolicies` in `PlayersService.swift`, run on the domain events right after the save. Tests: `meFollowsTheKeptPlayerOnMerge`, `removalClearsMeAndPublishesPlayerRemoved`.
- [ ] `WhoAmI` read model: id and name, displayed "Me (Callum)". Published to Stats.
- [ ] `Welcome` on first launch: name entry (creates the player and sets Me), then a skippable, replayable walkthrough

## UI (design language: 022)
- [ ] **Welcome:** a full-screen name entry on first launch, then a skippable walkthrough, which can be replayed from Settings
- [x] Me is shown as "Me (Callum)" on the hub and in Settings, and can be set or changed from either (`SetMe`)

## Non-goals
- Multiple Me identities

## Acceptance criteria
- Integration tests: set, follow on merge, clear on removal; the welcome creates the player and sets Me

**Implementation skills:** `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-05 audit):**
  - The `MeSetting` value is in `ios/Sources/Players/Domain/MeSetting.swift`. `set` and `clear` raise nothing, and it has pure `followingMerge` and `clearingOnRemoval` functions, which domain tests cover.
  - `SQLiteMeSettingStore` stores a single row.
  - `PlayersService.setMe` is reachable from Welcome, from the hub's Me row (`MeView`) and from Settings.
  - `AppRoot` shows `WelcomeView` full-screen until Me exists. Entering a name adds the player and sets Me.
  - Tests: `playersAndMeSurviveARelaunch` and `meMustBeAnExistingPlayer`.
- **Decisions:**
  - SetMe accepts an active or archived player.
  - The hub and Settings show "Me" next to the player's plate or name rather than the literal "Me (Callum)".
- **Remains:**
  - Wire the `UpdateMeOnMerge` and `ClearMeOnRemoval` policies to `PlayersMerged` and `PlayerRemoved`. That needs the 011 merge and remove use cases.
  - A `WhoAmI` read model published to Stats.
  - The skippable, replayable walkthrough and its Settings row.
  - Integration tests for following a merge, clearing on removal, and the welcome flow.
