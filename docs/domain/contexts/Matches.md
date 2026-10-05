# Bounded Context Canvas — Matches

**Classification:** Core
**Strategic revision:** ADR-0001 · boundaries: ADR-0002, ADR-0003

## Purpose
Fast, accurate scoring at the table: start a match from a setup, track frames and the break, time it, and end it as finished, abandoned or cancelled, with every action kept as the match's history. Owns templates, because a template is just a setup that isn't a live match yet.

## Scenarios
1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 20, 21, 25, 26, 27, 28, 29, 30, 31, 36, 37, 41, 43, 44, 46, 47 (and the cascades of 33, 42)

---

## Inbound Communication

| Source | Type | Description |
|--------|------|-------------|
| Scorer | Command | StartMatch, ChooseBreaker, CorrectBreaker, AwardFrame, RemoveFrame, PauseMatch, ResumeMatch, FinishMatch, AbandonMatch, CancelMatch, FinishAllMatches, CorrectMatchScore, MarkMatchFinished, DeleteMatch, OverrideMatchColour, DeleteTemplate, ChangeDefaults, SetLiveMatchLimit |
| Players | Query | Player names and colours (suggestions, display, colour clash check) |
| Players | Event | `PlayersMerged` → move matches and templates to the kept player, combine identical templates; `PlayerRemoved` → delete their matches and templates |
| Clock (iOS) | Command | WarnLongFrame (30 min, then every 10) |
| App lifecycle (iOS) | Command | AutoPauseMatch (launch after a kill), FlagStaleMatch (launch, idle ≥ 6 h) |
| Lock screen (iOS) | Command | AwardFrame, PauseMatch, ResumeMatch |
| Stats | Query | Head-to-head figures for the live screen; average frame time and same-weekday average match length for the stale-match prompt |

## Outbound Communication

| Destination | Type | Description |
|-------------|------|-------------|
| Stats | Event (published language) | All match events: `MatchStarted` (with setup), `BreakerChosen`, `BreakerCorrected`, `FrameWon`, `SetWon`, `MatchTargetReached`, `FrameRemoved`, `MatchPaused`, `MatchAutoPaused`, `MatchResumed`, `MatchFinished`, `MatchAbandoned`, `MatchCancelled`, `MatchScoreCorrected`, `MatchMarkedFinished`, `MatchDeleted`, `MatchColourOverridden` |
| Players | Query (open host) | "Is this player in a live match?" and "Have these two players ever played each other?" |
| iOS Notifications | Command (via adapter) | Long-frame warning |
| iOS Lock Screen | Command (via adapter) | Show, update, remove the Live Activity |

---

## Ubiquitous Language

| Term | Type | Definition within Matches | Avoid |
|------|------|---------------------------|-------|
| Match | Aggregate | One contest between two sides under a setup, from start to finished, abandoned or cancelled; its history of events is the record | "game" (a game is pool or snooker) |
| Side | Entity / concept | One of the two players in a match, by player ID, with its colour for this match (possibly temporary) | "player" when meaning the person |
| Setup | Value object | Two players (unordered), game, match style with targets, break rule; fixed once a match starts | "settings", "config" |
| Template | Aggregate | A setup that has been played, kept to start new matches quickly; listed by use count | "preset", "favourite" |
| Game | Value object | Pool or Snooker | — |
| Match style | Value object | Most frames wins, race to N frames, or sets (race to S sets, each race to F frames) | "mode", "type" |
| Target | Value object | Race to N (N ≥ 1); entered as race to N or best of M (odd), stored as race to ⌈M/2⌉ | — |
| Break rule | Value object | Alternate breaks or winner breaks | — |
| Breaker | Concept | The side breaking the current frame; derived from the first breaker, the frames and the break rule | — |
| Frame | Entity | One rack won by a side: number, set number, length, breaker; a corrected-in frame has no length | "game", "rack" |
| Set | Concept | A group of frames in a sets match, won by reaching the frame target | — |
| Live | State | Started and not ended: awaiting breaker, in play, paused, or awaiting confirmation | "active", "open" |
| Pause | Concept | Timers stopped, controls disabled except resume and the menu; manual, or automatic when the app is killed (applied on relaunch) | — |
| Stale match | Concept | A live match with no action for 6 hours, resolved when the app opens | — |
| Correction | Concept | A change recorded after a match has ended; the original stays in the history | "edit" |
| Match length / frame length | Value object | Elapsed time minus paused time; approximate | — |
| Match settings | Concept | Default game, style, break rule, and the live-match limit (default 10, max 100) | "preferences" |
| Live Activity | External concept | The lock-screen view of the oldest live match | — |

## Commands

| Command | Intent | Handled by |
|---------|--------|-----------|
| StartMatch | Begin a live match from a setup | Match; then Template policy |
| ChooseBreaker / CorrectBreaker | Set who breaks | Match |
| AwardFrame / RemoveFrame | Score or unscore a frame | Match |
| PauseMatch / ResumeMatch / AutoPauseMatch | Stop or restart the timers | Match |
| FinishMatch / AbandonMatch / CancelMatch / FinishAllMatches | End a live match | Match |
| FlagStaleMatch | Raise a stale match on launch | Match |
| CorrectMatchScore / MarkMatchFinished / DeleteMatch | Change an ended match | Match |
| OverrideMatchColour | Temporary colour for one side | Match |
| WarnLongFrame | Long-frame notification | Match |
| CreateTemplate / RecordTemplateUse / CombineTemplates / DeleteTemplate | Maintain templates | Template |
| ChangeDefaults / SetLiveMatchLimit | Change match settings | Match settings |

## Policies

| When | Then |
|------|------|
| `MatchStarted`, setup new | CreateTemplate |
| `MatchStarted`, setup known | RecordTemplateUse |
| `MatchStarted`, both sides same colour | offer OverrideMatchColour |
| `SetWon` / `MatchTargetReached` | Continue or Finish prompt; Undo → RemoveFrame |
| any match event | update the Live Activity |
| `FrameWon` / `MatchResumed` | restart / resume the long-frame timer |
| `MatchPaused` / `MatchAutoPaused` / match ended | stop the long-frame timer |
| `StaleMatchFlagged` | prompt: resume / end at a time / end capped / abandon / cancel |
| `PlayersMerged` (Players) | move matches and templates; CombineTemplates |
| `PlayerRemoved` (Players) | DeleteMatch and DeleteTemplate for that player |

---

## Business Rules
- Two different players; nobody plays themselves.
- Nothing but choosing the breaker until the first breaker is chosen.
- The breaker is derived, never stored per frame; sets don't affect it.
- While paused, only resume and the menu work.
- Only shutdown pauses a match.
- − never touches the timers.
- Reaching a target asks before ending; the end time is the winning frame's time.
- Target styles finished early become abandoned unless marked finished anyway.
- Abandoned → finished is allowed; finished → abandoned is not; cancelled never changes.
- Corrections after the end never overwrite; race-to corrections need exactly one side on the target.
- Live matches ≤ the live-match limit.
- Only a stale match's length can be capped.
- "Best of" is odd.
- Every new setup becomes a template when its match starts; a deleted template comes back.

## Aggregates
- `Match` — a match's lifecycle, frames, breaker, timers and corrections, as an event history
- `Template` — a played setup and its use count
- `MatchSettings` — defaults and the live-match limit (per device; raises no events)

## External Dependencies

| External Context | Relationship | Translation Needed? |
|-----------------|--------------|---------------------|
| Players | Customer (Players supplies; Matches uses names, colours and player events) | No: player IDs only |
| Stats | Customer of the head-to-head and average-time queries | No |
| iOS (Notifications, Live Activities, app lifecycle) | Anti-corruption layer | Yes: adapters at the edge |

## Team

| Role | Name |
|------|------|
| Domain Expert | Business owner |
| Tech Lead | Business owner |
| Team | Solo |

## Notes
- **Design for later:** a frame must be able to carry a loss reason (23) and a snooker points breakdown by colour; a match's event history must be able to take events from more than one device (shared matches); every match's full history must be uploadable (24).
- Deferred questions: Q1–Q4 in `docs/domain/decisions.md`.
