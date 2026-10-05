---
status: planned
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
updated_at: 2026-10-05T10:42:31.516183Z
---

# iOS lock-screen Live Activity

## Overview
The lock-screen live match (S47): an ActivityKit Live Activity with App Intents buttons. It is an anti-corruption adapter in infrastructure, so no iOS types enter the domain. Source: `docs/ddd-requirements.md` › Cross-cutting › Context boundaries.

## Requirements
- [ ] Exactly one Live Activity, showing `LockScreenState` (the oldest live match): sides, score, breaker, frame timer, paused (ADR-0004)
- [ ] `MatchStarted` with no other live match → show it. `MatchStarted` while another match is live → no change.
- [ ] Updates on the shown match's Stage 2 events: BreakerChosen/Corrected, FrameWon/Removed, Paused/AutoPaused/Resumed
- [ ] The shown match Finished/Abandoned/Cancelled → move to the next-oldest live match, or end the activity if none is left
- [ ] App Intents for +, pause and resume call the `AwardFrame`, `PauseMatch` and `ResumeMatch` use cases for the shown match
- [ ] It applies the Q4 resolution from the live use cases spec

## UI (design language: 022)
- [ ] The lock screen and the Dynamic Island (compact and expanded) follow 022:
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
