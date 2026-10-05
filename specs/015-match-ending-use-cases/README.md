---
status: planned
created: 2026-10-05
priority: high
tags:
- matches
- application
depends_on:
- '5'
- '6'
- '14'
parent: '1'
created_at: 2026-10-05T10:42:31.503356Z
updated_at: 2026-10-05T10:42:31.503356Z
---

# Match use cases: ending, stale & maintenance

## Overview
Command-side use cases for ending, maintaining and cleaning up matches. Source: `docs/ddd-requirements.md` › Matches › Match › Use Cases. Scenarios S10, S15, S16, S25–S31, S37, S43.

## Requirements
- [ ] `FinishMatch` (menu + confirmation, or the Finish prompt): an early finish of a target style returns "will be abandoned" unless `anyway`
- [ ] `AbandonMatch` and `CancelMatch`, with confirmation
- [ ] `FinishAllMatches`: finishable matches are finished, the others abandoned; one dialog if any will be abandoned
- [ ] `AutoPauseLiveMatches` (launch, after a kill; ADR-0004, ADR-0005):
  - Input: the last background time, if recorded
  - `findLive` → `autoPause(at:)` each running match, `at` = the later of the background time and that match's last action (the last action when none was recorded)
  - Already-paused matches untouched; runs before `FlagStaleMatches`
- [ ] `FlagStaleMatches`:
  - `findLive`, filtered by idle ≥ 6 h
  - Queries Stats' `AverageFrameTime` and `AverageMatchLength` (3 h fallback)
  - Prompts one match at a time
- [ ] `ResolveStaleMatch`
- [ ] `WarnLongFrame` (Clock-triggered): define a `NotificationScheduler` port here and test against an in-memory fake; the UserNotifications adapter is in 019
- [ ] `CorrectMatchScore` (timeline → Edit). Resolve or re-defer Q1 and Q2.
- [ ] `MarkMatchFinished`
- [ ] `DeleteMatch` (swipe + confirmation)

## UI (design language: 022)
- [ ] The live screen's **⋯ menu**:
  - Finish, Abandon and Cancel, each with a confirmation
  - Finishing a target style early warns "will be abandoned" and offers Finish anyway
- [ ] The **Finish?** and **Continue?** prompts (S15/S16) offer Undo
- [ ] A **Finish all** action in the hub's Live section, with one dialog when any match will be abandoned
- [ ] **Match detail actions** (013):
  - Correct score (Edit from the timeline)
  - Mark finished (abandoned matches only)
  - Delete (swipe, with confirmation)

## Non-goals
- The iOS lifecycle and notification adapters (their own specs)
- The merge and removal policies (in the players spec)

## Acceptance criteria
- One integration test per use case, including:
  - Finish all with mixed matches
  - Auto-pause at the background time, at a later lock-screen action, and at the last action when no background time was recorded
  - Stale prompt order
  - Stale with no history falling back to 3 h

**Implementation skill:** `ddd-application-layer` · **Tests:** `ddd-testing`
