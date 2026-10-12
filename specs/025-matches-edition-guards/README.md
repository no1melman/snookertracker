---
status: complete
created: 2026-10-12
priority: high
tags:
- upgrade
- matches
depends_on:
- '23'
- '10'
- '15'
- '18'
parent: '1'
created_at: 2026-10-12T15:13:40.460788Z
updated_at: 2026-10-12T15:36:48.332438Z
completed_at: 2026-10-12T15:36:48.332438Z
transitions:
- status: in-progress
  at: 2026-10-12T15:26:47.338422Z
- status: complete
  at: 2026-10-12T15:36:48.332438Z
---
# Matches edition guards

## Overview
Enforce the Free limits on the `Match` aggregate, its use cases and reads, reading `CurrentEdition` and reacting to `AppLocked` (Upgrade, ADR-0011). Source: `docs/ddd-requirements.md` Changes section rows for `Match`. Scenarios S1, S2, S7, S8, S11, S14, S22, S27–S30, S43, S44, S46, S47, S51, S52.

## Requirements
- [x] Invariant: a Paused match knows how it was paused (by hand: `MatchPaused`; automatically: `MatchAutoPaused`), for the edition guard on `ResumeMatch`
- [x] `MatchRepository.isAmongNewestEnded(MatchId, n)`: whether an ended match is among the n most recently ended
- [x] `StartMatch`: guards: live-match limit (MatchSettings; **Free: 1**); **Free: style must be most frames wins and break rule alternate, else refused → upgrade offer (S52)**
- [x] `PauseMatch` / `ResumeMatch`: **Free: `PauseMatch` refused → "Upgrade now" on the pause button (S52); `ResumeMatch` refused for a match paused by hand, allowed for one auto-paused after a kill**
- [x] `FinishAllMatches`: **paid** (Free has one live match)
- [x] `OverrideMatchColour`: **not offered while Free** (no colours shown)
- [x] `CorrectMatchScore`: **Free: only if `isAmongNewestEnded(id, 10)`**
- [x] `DeleteMatch`: **Free: Scorer deletions only if `isAmongNewestEnded(id, 10)`; the S42 cascade is never limited**
- [x] `RemoveLiveActivityOnLock`: policy on `AppLocked` (Upgrade); removes the Live Activity; live matches carry on unchanged (style, break rule, pauses kept)
- [x] Reads:
  - `LiveMatches`: colours omitted while Free
  - `LiveMatchScreen`: **Free:** no colours, head-to-head greyed with an upgrade prompt, pause button shows "Upgrade now"
  - `LockScreenState`: **Unlocked only (none while Free)**

### UI (design language: 022)
- [x] Refused start, pause, finish all, correction and deletion route to `ShowUpgradeOffer`; the pause offer is in place

## Non-goals
- Templates and MatchSettings guards (separate spec); the offer screens

## Acceptance criteria
**Free limits** (verbatim): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

- Unit: the pause-kind invariant
- Integration: Free refuses a 2nd live match, other styles and break rules, manual pause, resuming a manual pause, corrections and deletions beyond the newest 10; Free allows auto-pause and its resume; `AppLocked` removes the Live Activity and leaves live matches unchanged

**Implementation skills:** `ddd-tactical-patterns`, `ddd-repositories`, `ddd-application-layer`, `ddd-cqrs`, `ddd-domain-events` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-12):**
  - Domain: `Match.pauseKind` (`PauseKind.byHand` / `.automatic`, nil unless Paused), derived from the open pause, so from `MatchPaused` / `MatchAutoPaused`. No new stored data or events.
  - `MatchRepository.isAmongNewestEnded(id, n)`, served by the `match_streams` index (no migration).
  - `MatchUseCases` reads `CurrentEdition` and throws `UpgradeRequired`: StartMatch (`raceTo` / `sets` / `winnerBreaks` / `severalLiveMatches`), PauseMatch and ResumeMatch of a pause by hand (`manualPause`), FinishAllMatches and its preview (`severalLiveMatches`), OverrideMatchColour (`colours`), CorrectMatchScore and the Scorer's DeleteMatch (`fullHistory`).
  - The S42 cascade (`DeleteMatchesOnPlayerRemoved(matches:)`) deletes through `deleteOnPlayerRemoved`, which has no edition guard. Auto-pause and stale resolution have no guard either.
  - `RemoveLiveActivityOnLock` policy (Matches Application) with a `LiveActivityPort`. `LockScreenActivity` implements the port by ending the activity. It is wired in `LiveActivityComposition`.
  - Reads: `LiveMatchesProjection(players:edition:)` omits colours while Free (`LiveSide.noColour`, `showsColour`) and never reports a colour clash. `LiveMatchScreen` gains `showsColours`, `headToHeadLocked`, `Controls.pauseOffersUpgrade` and `Controls.resumeOffersUpgrade`. `LockScreenState` is nil while Free. On `AppUnlocked` / `AppLocked` the projection redraws (`subscribeToEdition`).
  - UI: the pause button shows "Upgrade now", as does resuming a pause by hand. The head-to-head strip is greyed and has an upgrade prompt. There are no colour plates on the live, live list and stale screens. A refused start or Finish all opens `ShowUpgradeOffer` (`attemptOrOffer`), and so does a refused History correction or deletion (`AppContainer`).
  - Tests: `PauseKindTests` (domain) and `MatchesEditionGuardsTests` (integration, `FixedEdition`) cover every acceptance item.
- **Decisions:**
  - "Newest ended" uses History's order: start time newest first, ties by id. It counts finished, abandoned and cancelled matches (deleted ones don't count), matching spec 027's visible set.
  - StartMatch checks the Free table first (style, break rule, `FreeLimits.allowsAnotherLiveMatch`) and then `MatchSettingsService.effectiveLiveMatchLimit` (spec 026). Both say 1 while Free, so they agree. The Free refusal is `UpgradeRequired(.severalLiveMatches)`, which opens the offer, not the S44 limit alert.
  - Resuming is refused only for a pause by hand while Free. The pause kind comes from the stored match, so a pause made before a revocation stays paid.
  - A refused History deletion or correction opens the offer and returns quietly instead of showing an error alert.
- **Follow-up (2026-10-12): a refused correction is no longer a save.** The correction port returned `[]` on a Free refusal, which the edit sheet read as saved. `MatchDetailActions.correctScore` now returns a `CorrectionOutcome` (`.saved`, `.needsConfirming`, `.refused(feature)`); on `.refused` the sheet closes without saving and the detail opens the offer once the sheet is gone (the offer is a root sheet, so it waits for the edit sheet). `delete` now returns whether the match was deleted, so a refused deletion leaves the detail open instead of popping it as if deleted. The adapters live in `HistoryMaintenance` (AppComposition), tested over the real use cases in `HistoryMaintenanceTests` (new `AppCompositionTests` target).
- **Remains:**
  - The offer screens themselves (spec 029).
