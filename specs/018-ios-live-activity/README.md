---
status: in-progress
created: 2026-10-05
priority: medium
tags:
- ios
- infrastructure
depends_on:
- '10'
- '9'
parent: '1'
created_at: 2026-10-05T10:42:31.516183Z
updated_at: 2026-10-05T20:46:00.909821Z
transitions:
- status: in-progress
  at: 2026-10-05T20:46:00.909821Z
---

# iOS lock-screen Live Activity

## Overview
The lock-screen live match (S47): an ActivityKit Live Activity with App Intents buttons. It is an anti-corruption adapter in infrastructure, so no iOS types enter the domain. Source: `docs/ddd-requirements.md` › Cross-cutting › Context boundaries.

## Requirements
- [x] Exactly one Live Activity, showing `LockScreenState` (the oldest live match): sides, score, breaker, frame timer, paused (ADR-0004)
- [x] `MatchStarted` with no other live match → show it. `MatchStarted` while another match is live → no change.
- [x] Updates on the shown match's Stage 2 events: BreakerChosen/Corrected, FrameWon/Removed, Paused/AutoPaused/Resumed
- [x] The shown match Finished/Abandoned/Cancelled → move to the next-oldest live match, or end the activity if none is left
- [x] App Intents for +, pause and resume call the `AwardFrame`, `PauseMatch` and `ResumeMatch` use cases for the shown match
- [ ] It applies the Q4 resolution from the live use cases spec

## UI (design language: 022)
- [x] The lock screen and the Dynamic Island (compact and expanded) follow 022:
  - Colour plates and names, and the score in monospaced digits
  - The frame timer
  - **+** per player, and Pause or Resume
  - A clear paused state

## Non-goals
- Widgets beyond the Live Activity

## Acceptance criteria
- Adapter tests:
  - The first `MatchStarted` shows an activity; a second live match doesn't replace it
  - The shown match's events map to activity content; other matches' events are ignored
  - Ending the shown match hands over to the next-oldest, or ends the activity when none is left
- The intents invoke the use cases (verified with an in-memory composition)
- Checked manually on a device or simulator

**Implementation skill:** `ddd-application-layer` (ports) · **Tests:** `ddd-testing`

## Progress (2026-10-05)
- `LockScreenState` + `LockScreenStateQuery`: `ios/Sources/Matches/Application/LockScreenState.swift`, a view over `LiveMatchesProjection` (oldest row). Tests: `ios/Tests/Matches/IntegrationTests/LockScreenStateTests.swift`.
- Adapter: `ios/Sources/Shared/iOSAdapters/LockScreenActivity.swift` refreshes on every `MatchEventPublished` and diffs the state, so other matches' events change nothing; hand-over is an update of the same activity. `ActivityKitLockScreenPresenter` does local updates only (no push), retries a refused start on return to the foreground, and adopts or ends activities left by an earlier run. Tests: `ios/Tests/Shared/iOSAdaptersTests/`.
- Shared module `LiveActivityShared`: the activity content plus `MatchActivityCommandRoute`. Intents (`ios/LiveActivityWidget/Intents/`) are compiled into the app and the extension. As `LiveActivityIntent`s they run in the app process, so there is no App Group or shared DB. `LockScreenLiveActivity.install()` runs from the app's `init`, so background launches for a button work too.
- Widget extension `LiveActivityWidget` (xcodegen). The app has `NSSupportsLiveActivities`. No extra entitlements, so it works with the free personal team.
- Q4 is still deferred. Lock-screen and in-app commands are serialised on the main actor, so they apply in the order they arrive. + is offered only while In Play.
- Open: tie-break by creation order when two matches start in the same instant (`LiveMatchesProjection` sorts by start time only). Visual check of the lock screen is still to do on a device or the Simulator GUI. The headless simulator confirmed that the activity goes active and renders.

## Progress (2026-10-06)
- Lock-screen redesign: the old layout was about 157pt, close to the roughly 160pt cap, with crowded names, floating colour plates and washed-out paused scores. It is now one row per side (colour bar, name and breaker dot, 34pt score) around the frame clock, over one 40pt row of controls, about 128pt in all. The text-only states (choose breaker, target reached) are a single short line. Paused dims scores and the timer by opacity rather than switching to `.secondary`, so they don't pick up the background tint. The Dynamic Island uses the same paused treatment.
- Checked in a scratch harness app on the iPhone 18 Pro simulator that renders the real widget views (Xcode 27 has no Simulator GUI to lock the device, and `simctl` screenshots don't capture the Dynamic Island). The real lock screen still needs a check on the device.
