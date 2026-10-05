---
status: complete
created: 2026-10-05
priority: medium
tags:
- matches
depends_on:
- '3'
parent: '1'
created_at: 2026-10-05T10:42:31.471330Z
updated_at: 2026-10-05T20:51:19.682822Z
completed_at: 2026-10-05T20:51:19.682822Z
transitions:
- status: complete
  at: 2026-10-05T20:51:19.682822Z
---

# Match settings

## Overview
Per-device `MatchSettings`: the defaults for a new match and the live-match limit. Changes apply only to matches started afterwards. It raises no events. Source: `docs/ddd-requirements.md` › Matches › MatchSettings. Scenarios S2, S11, S20, S21, S44.

## Requirements
- [x] `MatchSettings.initial`: pool, mostFramesWins, alternate, limit 10
- [x] `changeDefaults(game?, style?, breakRule?)` refuses invalid targets
- [x] `setLiveMatchLimit(n)`: guard 1…100
- [x] A `MatchSettingsStore` port and adapter (`get`, `save`; one per device)
- [x] Use cases `ChangeMatchDefaults` and `SetLiveMatchLimit`
- [x] `MatchSettingsView` read model: game, style + targets, break rule, limit

## UI (design language: 022)
- [x] The **Settings** screen (inset grouped list) from `MatchSettingsView`:
  - Default game, match style and targets, and break rule
  - Live-match limit as a stepper from 1 to 100
  - A footer: changes apply to new matches only
  - The same screen hosts Me and Replay walkthrough (012)
- [x] The New Game details step opens with these defaults

## Non-goals
- Enforcing the limit (that is `StartMatch`, in the live use cases spec)

## Acceptance criteria
- Domain unit tests: initial defaults, limit bounds, invalid targets refused
- Integration test: defaults are applied to the details screen's initial values

**Implementation skills:** `ddd-tactical-patterns`, `ddd-repositories`, `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-05 audit):**
  - The domain values are `MatchDefaults.initial` and `LiveMatchLimit` (1…100, default 10) in `Sources/Matches/Domain/SettingsValues.swift`.
  - `MatchSettingsValues` and the `MatchSettingsStore` port are in `Application/MatchRepository.swift`. `SQLiteMatchSettingsStore` stores them as a single JSON row.
  - `MatchSettingsService` covers `ChangeMatchDefaults`, `SetLiveMatchLimit` and the `MatchSettingsView` read model.
  - The UI is `MatchDefaultsSection` inside the hub's `SettingsView`: game, style and targets, break rule, a 1–100 stepper and the "new matches only" footer. `NewGameView.loadDefaults` opens New Game with these defaults.
  - Tests: `ValueObjectTests` (initial defaults, limit bounds, `Target` refusals) and `defaultsAreStoredAndOfferedToNewGame` (persistence, `invalidTargets` refusal).
- **Decisions:**
  - Settings is not a separate domain aggregate. Validity comes from the value objects, the application service owns the per-device document, and it raises no events.
  - The limit setter clamps to 1…100 to match the stepper.
  - The app-layer `MatchStyle` has no sets yet, so sets can't be chosen as a default.
- **Remains:** the Replay walkthrough row on the Settings screen comes with 012. The integration test checks the defaults the service offers, not the view's state.
