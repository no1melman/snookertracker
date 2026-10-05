---
status: in-progress
created: 2026-10-05
priority: critical
tags:
- matches
- application
depends_on:
- '4'
- '6'
- '7'
- '9'
parent: '1'
created_at: 2026-10-05T10:42:31.483846Z
updated_at: 2026-10-05T20:51:20.116577Z
transitions:
- status: in-progress
  at: 2026-10-05T20:51:20.116577Z
---

# Match use cases: start & play

## Overview
Command-side use cases for starting and playing a match. Source: `docs/ddd-requirements.md` › Matches › Match › Use Cases. Scenarios S1, S2, S4–S8, S11, S41, S44, S46, S47.

**Also depends on** 008 (starting from a template needs `TemplateList`). Not in frontmatter: `leanspec rel` is not migrated yet.

## Requirements
- [ ] `StartMatch`:
  - Triggered by the Scorer, from a template or from entered details
  - Enforces the live-match limit from `MatchSettings`
  - Asks "already in a live match?" (`IsPlayerInLiveMatch`)
  - Load settings → `Match.start` → save → dispatch
- [ ] `ChooseBreaker` and `CorrectBreaker` (from the match menu)
- [ ] `AwardFrame` (in the app or on the lock screen). **Resolve Q3** (+ while a Finish/Continue prompt shows) and **Q4** (lock-screen + vs in-app −) with the business owner. Record each answer through `/ddd delta`.
- [x] `RemoveFrame` (−, or Undo on a prompt)
- [x] `PauseMatch` and `ResumeMatch` (in the app or on the lock screen)
- [ ] `OverrideMatchColour`: policy on `MatchStarted` when the sides share a colour and the Scorer accepts
- [x] Every use case follows load → mutate → save → dispatch

## UI (design language: 022)
- [x] **New Game › Enter details:**
  - Game, and players from `PlayerSuggestions` with inline add (011)
  - Style and targets as "race to" or "best of", odd numbers only
  - Break rule, with defaults from 007
- [ ] **Start outcomes:**
  - The live-match limit refusal is an alert that explains the limit and links to Settings
  - The "already in a live match?" confirmation
  - The colour clash (S46) is a confirmation offering a temporary colour
- [x] **Choose breaker:** tap a player, then the live screen opens
- [ ] **Live screen controls:**
  - Per player, a large **+** and a smaller, secondary **−**, both with haptics
  - Pause and Resume in the toolbar; Correct breaker in the ⋯ menu
  - Disabled when there is no breaker, when paused, and − at 0

## Non-goals
- Ending and stale use cases (separate spec)
- iOS lock-screen wiring (Live Activity spec)

## Acceptance criteria
- One integration test per use case, including the live-match limit refusal and the "already live" confirmation
- Q3 and Q4 are answered and recorded, or explicitly re-deferred in `docs/domain/decisions.md`

**Implementation skill:** `ddd-application-layer` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-05 audit):**
  - `MatchUseCases` (`Sources/Matches/Application/MatchUseCases.swift`) covers StartMatch (enforcing the live-match limit), ChooseBreaker, AwardFrame, RemoveFrame, Pause and Resume, plus Finish, Abandon and Cancel. Each one is load → behaviour → save → project → dispatch.
  - UI: `NewGameView` has defaults, suggestions with inline add, and race-to/best-of-odd steppers. `LiveMatchView` has "X breaks" buttons, a large + and smaller −, haptics through `sensoryFeedback`, and Pause/Resume in the toolbar.
  - Tests are in `MatchUseCaseTests`.
- **Decisions:**
  - Q3: + is disabled while the "X wins?" Finish/Undo prompt shows, because the domain refuses `awardFrame` in AwaitingConfirmation and Undo is − on the winning frame.
  - A concurrency conflict surfaces as `changedElsewhere`.
  - Choosing the breaker happens on the live screen itself.
- **Remains:**
  - StartMatch from a template (008).
  - The "already in a live match?" check (needs the 009 OHS).
  - The CorrectBreaker use case and its ⋯ menu item.
  - The OverrideMatchColour policy and the colour-clash prompt.
  - The limit alert's link to Settings.
  - Lock-screen wiring (018).
  - Recording Q3 and resolving or re-deferring Q4 in `docs/domain/decisions.md`.
  - Tests for correct breaker, override colour and "already live".
