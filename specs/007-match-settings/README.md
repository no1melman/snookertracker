---
status: planned
created: 2026-10-05
priority: medium
tags:
- matches
depends_on:
- '3'
parent: '1'
created_at: 2026-10-05T10:42:31.471330Z
updated_at: 2026-10-05T10:42:31.471330Z
---

# Match settings

## Overview
Per-device `MatchSettings`: the defaults for a new match and the live-match limit. Changes apply only to matches started afterwards. It raises no events. Source: `docs/ddd-requirements.md` › Matches › MatchSettings. Scenarios S2, S11, S20, S21, S44.

## Requirements
- [ ] `MatchSettings.initial`: pool, mostFramesWins, alternate, limit 10
- [ ] `changeDefaults(game?, style?, breakRule?)` refuses invalid targets
- [ ] `setLiveMatchLimit(n)`: guard 1…100
- [ ] A `MatchSettingsStore` port and adapter (`get`, `save`; one per device)
- [ ] Use cases `ChangeMatchDefaults` and `SetLiveMatchLimit`
- [ ] `MatchSettingsView` read model: game, style + targets, break rule, limit

## UI (design language: 022)
- [ ] The **Settings** screen (inset grouped list) from `MatchSettingsView`:
  - Default game, match style and targets, and break rule
  - Live-match limit as a stepper from 1 to 100
  - A footer: changes apply to new matches only
  - The same screen hosts Me and Replay walkthrough (012)
- [ ] The New Game details step opens with these defaults

## Non-goals
- Enforcing the limit (that is `StartMatch`, in the live use cases spec)

## Acceptance criteria
- Domain unit tests: initial defaults, limit bounds, invalid targets refused
- Integration test: defaults are applied to the details screen's initial values

**Implementation skills:** `ddd-tactical-patterns`, `ddd-repositories`, `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`
