---
status: planned
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
updated_at: 2026-10-12T15:13:40.460788Z
---

# Matches edition guards

## Overview
Enforce the Free limits on the `Match` aggregate, its use cases and reads, reading `CurrentEdition` and reacting to `AppLocked` (Upgrade, ADR-0011). Source: `docs/ddd-requirements.md` Changes section rows for `Match`. Scenarios S1, S2, S7, S8, S11, S14, S22, S27–S30, S43, S44, S46, S47, S51, S52.

## Requirements
- [ ] Invariant: a Paused match knows how it was paused (by hand: `MatchPaused`; automatically: `MatchAutoPaused`), for the edition guard on `ResumeMatch`
- [ ] `MatchRepository.isAmongNewestEnded(MatchId, n)`: whether an ended match is among the n most recently ended
- [ ] `StartMatch`: guards: live-match limit (MatchSettings; **Free: 1**); **Free: style must be most frames wins and break rule alternate, else refused → upgrade offer (S52)**
- [ ] `PauseMatch` / `ResumeMatch`: **Free: `PauseMatch` refused → "Upgrade now" on the pause button (S52); `ResumeMatch` refused for a match paused by hand, allowed for one auto-paused after a kill**
- [ ] `FinishAllMatches`: **paid** (Free has one live match)
- [ ] `OverrideMatchColour`: **not offered while Free** (no colours shown)
- [ ] `CorrectMatchScore`: **Free: only if `isAmongNewestEnded(id, 10)`**
- [ ] `DeleteMatch`: **Free: Scorer deletions only if `isAmongNewestEnded(id, 10)`; the S42 cascade is never limited**
- [ ] `RemoveLiveActivityOnLock`: policy on `AppLocked` (Upgrade); removes the Live Activity; live matches carry on unchanged (style, break rule, pauses kept)
- [ ] Reads:
  - `LiveMatches`: colours omitted while Free
  - `LiveMatchScreen`: **Free:** no colours, head-to-head greyed with an upgrade prompt, pause button shows "Upgrade now"
  - `LockScreenState`: **Unlocked only (none while Free)**

### UI (design language: 022)
- [ ] Refused start, pause, finish all, correction and deletion route to `ShowUpgradeOffer`; the pause offer is in place

## Non-goals
- Templates and MatchSettings guards (separate spec); the offer screens

## Acceptance criteria
**Free limits** (verbatim): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

- Unit: the pause-kind invariant
- Integration: Free refuses a 2nd live match, other styles and break rules, manual pause, resuming a manual pause, corrections and deletions beyond the newest 10; Free allows auto-pause and its resume; `AppLocked` removes the Live Activity and leaves live matches unchanged

**Implementation skills:** `ddd-tactical-patterns`, `ddd-repositories`, `ddd-application-layer`, `ddd-cqrs`, `ddd-domain-events` · **Tests:** `ddd-testing`
