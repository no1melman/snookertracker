# Snooker Tracker — Domain

**Language:** Swift
**Model revision:** ADR-0005 (2026-10-05) — history in `docs/adr/`, fallout in [decisions.md](./decisions.md)

## Context
An iOS app for tracking pool and snooker matches between friends, scored live on one phone by whoever is holding it. Pool is the default game and *most frames wins* the default match style; both defaults can be changed in settings. A match can also be a *race to* N frames or *sets* (race to S sets, each race to F frames), entered as "race to" or "best of" (odd numbers only). The scorer starts a match from a template (a setup played before) or by entering the details, taps who breaks, then taps + or − under each player as frames are won or corrected; the break moves automatically. Matches can be paused, left and returned to, and finished, abandoned or cancelled. Every match is kept as a history (frames, frame times, breakers, later corrections), stored on the device for now and uploadable in full when a web side arrives. Stats can be filtered by opponent and day of the week (e.g. "Asher on Fridays"), and regular match-ups can be grouped into series with a monthly summary.

## The picture
- [System map](./system-map.md) — actors, aggregates, external systems, and the commands/events between them, by scenario
- [Event map](./event-map.md) — every event: what raises it, what causes it, what reacts, and each aggregate's lifecycle

## Scenarios

Status: new = not built · existing = code does this today · changing = code differs from the model (see the scenario's *Change from today*)

`[?]` = has a deferred open question in [decisions.md](./decisions.md) (revisit during implementation; does not block the MVP).

| # | Scenario | Type | Status | Actor | Key events |
|---|----------|------|--------|-------|------------|
| 1 | [Start a match from a template](./scenarios/01-start-match-from-template.md) | YOU | new | Scorer | `MatchStarted`, `TemplateUsed` |
| 2 | [Start a match by entering details](./scenarios/02-start-match-by-entering-details.md) | YOU | new | Scorer | `MatchStarted`, `TemplateCreated` |
| 3 | [Add a new player](./scenarios/03-add-new-player.md) | YOU | new | Scorer | `PlayerAdded` |
| 4 | [Choose who breaks](./scenarios/04-choose-breaker.md) | YOU | new | Scorer | `BreakerChosen` |
| 5 [?] | [Award a frame](./scenarios/05-award-frame.md) | YOU | new | Scorer | `FrameWon` |
| 6 [?] | [Take a frame back](./scenarios/06-take-frame-back.md) | YOU | new | Scorer | `FrameRemoved` |
| 7 | [Pause a match](./scenarios/07-pause-match.md) | YOU | new | Scorer | `MatchPaused` |
| 8 | [Resume a match](./scenarios/08-resume-match.md) | YOU | new | Scorer | `MatchResumed` |
| 9 | [Return to a live match](./scenarios/09-return-to-live-match.md) | YOU | new | Scorer | raises nothing |
| 10 | [Finish a match](./scenarios/10-finish-match.md) | YOU | new | Scorer | `MatchFinished` |
| 11 | [New match while one is live](./scenarios/11-new-match-while-live.md) | YOU | new | Scorer | raises nothing |
| 12 | [Create or use a template from a setup](./scenarios/12-create-template-from-setup.md) | AUTO | new | policy (reaction) | `TemplateCreated`, `TemplateUsed` |
| 14 | [Show head-to-head on the live match](./scenarios/14-show-head-to-head.md) | AUTO | new | policy (reaction) | raises nothing |
| 15 [?] | [Race-to match won](./scenarios/15-race-to-match-won.md) | AUTO | new | policy (reaction) | `MatchTargetReached` |
| 16 [?] | [Set won, sets match won](./scenarios/16-sets-set-and-match-won.md) | AUTO | new | policy (reaction) | `SetWon`, `MatchTargetReached` |
| 17 | [View past matches](./scenarios/17-view-past-matches.md) | YOU | new | Scorer | raises nothing |
| 18 | [Stats by opponent](./scenarios/18-stats-by-opponent.md) | YOU | new | Scorer | raises nothing |
| 19 | [Stats by day of the week](./scenarios/19-stats-by-day-of-week.md) | YOU | new | Scorer | raises nothing |
| 20 | [Change the default game](./scenarios/20-change-default-game.md) | YOU | new | Scorer | raises nothing |
| 21 | [Change the default match style and break rule](./scenarios/21-change-default-match-style.md) | YOU | new | Scorer | raises nothing |
| 22 | [Set a player's colour](./scenarios/22-set-player-colour.md) | YOU | new | Scorer | `PlayerColourChanged` |
| 25 | [Abandon a match](./scenarios/25-abandon-match.md) | YOU | new | Scorer | `MatchAbandoned` |
| 26 | [Cancel a match](./scenarios/26-cancel-match.md) | YOU | new | Scorer | `MatchCancelled` |
| 27 | [Auto-pause when the app is killed](./scenarios/27-auto-pause-on-shutdown.md) | AUTO | new | App lifecycle | `MatchAutoPaused` |
| 28 | [Resolve a stale match](./scenarios/28-resolve-stale-match.md) | AUTO | new | App lifecycle | `StaleMatchFlagged` |
| 29 [?] | [Correct an ended match's score](./scenarios/29-correct-ended-match-score.md) | YOU | new | Scorer | `MatchScoreCorrected` |
| 30 | [Delete a match](./scenarios/30-delete-match.md) | YOU | new | Scorer | `MatchDeleted` |
| 31 | [Turn an abandoned match into a finished one](./scenarios/31-mark-abandoned-match-finished.md) | YOU | new | Scorer | `MatchMarkedFinished` |
| 32 | [Rename a player](./scenarios/32-rename-player.md) | YOU | new | Scorer | `PlayerRenamed` |
| 33 | [Merge two players](./scenarios/33-merge-players.md) | YOU | new | Scorer | `PlayersMerged` |
| 34 | [Archive a player](./scenarios/34-archive-player.md) | YOU | new | Scorer | `PlayerArchived` |
| 35 | [Unarchive a player](./scenarios/35-unarchive-player.md) | YOU | new | Scorer | `PlayerUnarchived` |
| 36 | [Delete a template](./scenarios/36-delete-template.md) | YOU | new | Scorer | `TemplateDeleted` |
| 37 | [Warn about a long frame](./scenarios/37-warn-long-frame.md) | AUTO | new | Clock | `LongFrameWarned` |
| 38 [?] | [Monthly series summary](./scenarios/38-monthly-series-summary.md) | AUTO | new | Clock | `SeriesSummaryIssued` |
| 39 | [Create a series](./scenarios/39-create-series.md) | YOU | new | Scorer | `SeriesCreated` |
| 40 | [Change or delete a series](./scenarios/40-change-or-delete-series.md) | YOU | new | Scorer | `SeriesChanged`, `SeriesDeleted` |
| 41 | [Correct the breaker](./scenarios/41-correct-breaker.md) | YOU | new | Scorer | `BreakerCorrected` |
| 42 | [Remove an archived player](./scenarios/42-remove-archived-player.md) | YOU | new | Scorer | `PlayerRemoved` |
| 43 | [Finish all live matches](./scenarios/43-finish-all-live-matches.md) | YOU | new | Scorer | `MatchFinished`, `MatchAbandoned` |
| 44 | [Set the live-match limit](./scenarios/44-set-live-match-limit.md) | YOU | new | Scorer | raises nothing |
| 45 | [Set who I am](./scenarios/45-set-who-i-am.md) | YOU | new | Scorer | raises nothing |
| 46 | [Offer a temporary colour](./scenarios/46-offer-temporary-colour.md) | AUTO | new | policy (reaction) | `MatchColourOverridden` |
| 47 [?] | [Live match on the lock screen](./scenarios/47-lock-screen-live-match.md) | AUTO | new | policy (reaction) | raises nothing |
| 48 | [First-launch welcome](./scenarios/48-first-launch-welcome.md) | YOU | new | Scorer | `PlayerAdded` |

Counts: new 45 · existing 0 · changing 0 · retired 0 · merged 1 · out of scope (later) 2 — numbers 13, 23, 24 are in [decisions.md](./decisions.md)

## Domain Vocabulary
See [glossary.md](./glossary.md).

## Bounded contexts
See [context-map.md](./context-map.md) and [contexts/](./contexts/) once strategic design has run.

## Decisions and open questions
See [decisions.md](./decisions.md).
