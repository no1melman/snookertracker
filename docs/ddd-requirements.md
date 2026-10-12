# DDD Requirements — Snooker Tracker (Matches · Players · Stats · Upgrade)

> The architectural constitution for Snooker Tracker's four bounded contexts, derived from `docs/domain/` at model revision ADR-0010 and the strategic design (ADR-0002, ADR-0003, ADR-0011).
> Every item below must exist in the implementation. Feed the items into your spec or planning tool as acceptance criteria; do not alter the constraints or invariants there.
> Each item carries: the scenarios it comes from · an **Action** (build · preserve · migrate) · the **Implementation skill** to invoke.
> Greenfield: every scenario is `new`, so every item is **build**.

**Language:** Swift
**Model revision:** ADR-0010 (2026-10-12)
**Strategic revision:** ADR-0010 (boundaries ADR-0002, ADR-0003, ADR-0011)
**Previous requirements revision:** ADR-0005

## Changes since last revision

Caused by ADR-0010 (Free and Unlocked editions) and ADR-0011 (Upgrade context owns the edition and Free limits), 2026-10-12. Hand this section to the planner. The previous revision covered ADR-0004 and ADR-0005. ADR-0006 to ADR-0009 were delivered through specs; only the stale Q6 row is tidied here.

**Free limits** (the acceptance figures for every guard below): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

| Change | Item | Scenarios | Action | Notes |
|--------|------|-----------|--------|-------|
| ADDED | Context **Upgrade** › `Edition` (value objects, aggregate, events, store, use cases, reads, tests) | S49–S53 | build | Whole section below (ADR-0010, ADR-0011) |
| ADDED | Upgrade › Domain Events › `AppUnlocked`, `AppLocked` | S49, S50, S51, S53 | build | Stage 2: Upgrade's published language, consumed by Matches, Players and Stats (ADR-0011) |
| ADDED | Upgrade › Read › `CurrentEdition` (open host) | S1–S3, S7, S8, S11, S14–S19, S21, S22, S29, S30, S35, S36, S38–S40, S43, S44, S46, S47, S52 | build | Edition + `FreeLimits`; served from the local cache, works offline (ADR-0011) |
| CHANGED | `Match` › Aggregate › invariant: how a match was paused | S7, S8, S27, S28 | build | A Paused match knows whether it was paused by hand (`MatchPaused`) or automatically (`MatchAutoPaused`); `ResumeMatch` needs it for the edition guard |
| CHANGED | `Match` › Use Cases › `StartMatch` | S1, S2, S11, S44 | build | Free: refuse when a match is live (limit 1), and when the style isn't most frames wins or the break rule isn't alternate → upgrade offer |
| CHANGED | `Match` › Use Cases › `PauseMatch` / `ResumeMatch` | S7, S8, S27, S28 | build | Free: `PauseMatch` refused; `ResumeMatch` refused only for a match paused by hand (auto-paused resumes stay free) |
| CHANGED | `Match` › Use Cases › `FinishAllMatches`, `OverrideMatchColour` | S43, S46 | build | Paid; the colour-clash offer isn't made while Free |
| CHANGED | `Match` › Use Cases › `CorrectMatchScore`, `DeleteMatch` | S29, S30 | build | Free: only the newest 10 ended matches; the removal cascade (S42) is never limited |
| ADDED | `Match` › Use Cases › `RemoveLiveActivityOnLock` | S47, S51 | build | Policy on `AppLocked`; live matches carry on unchanged |
| ADDED | `Match` › Repository Port › `isAmongNewestEnded(MatchId, n)` | S29, S30 | build | Supports the Free guard without asking Stats |
| CHANGED | `Match` › Read › `LiveMatchScreen`, `LockScreenState`, `LiveMatches` | S7, S14, S22, S47 | build | Free: head-to-head greyed with an upgrade prompt, the pause button shows "Upgrade now", no colours, no Live Activity |
| CHANGED | `Template` › Use Cases › `CreateOrUseTemplate` | S12 | build | Runs regardless of edition (recorded silently while Free) |
| CHANGED | `Template` › Use Cases › `DeleteTemplate`; Read › `TemplateList` | S1, S36 | build | Free: delete refused (the cascade from S42 isn't); the list is replaced by an "Upgrade now" prompt in place |
| CHANGED | `MatchSettings` › Use Cases › `ChangeMatchDefaults`, `SetLiveMatchLimit`; effective limit | S11, S21, S44 | build | Free: style and break defaults and the limit setting refused; effective limit 1 whatever is stored; the game default (S20) stays free |
| CHANGED | `Player` › Use Cases › `AddPlayer`, `UnarchivePlayer` | S2, S3, S35, S48 | build | Free: refused when 5 players are active → upgrade offer; players over the cap after a revocation stay |
| ADDED | `Player` › Repository Port › `countActive()` | S3, S35 | build | Active players only (archived, merged away and removed excluded) |
| CHANGED | `Player` › Use Cases › `ChangePlayerColour`; Read › colour fields | S22 | build | Free: refused; colours kept but left out of every read while Free |
| CHANGED | Stats › Read › `PastMatches`, `MatchTimeline` | S17 | build | Free: the newest 10 ended matches plus a hidden count; the timeline only for those |
| CHANGED | Stats › Read › `HeadToHead`, `Stats(filter)` | S14, S18, S19 | build | Free: locked (no figures returned); the projections keep building so unlocking shows everything at once |
| CHANGED | `Series` › Use Cases › `CreateSeries`, `ChangeSeries`, `DeleteSeries`, `IssueMonthlySummaries`; Read › `SeriesList`, `MonthlySummary` | S38, S39, S40 | build | Free: refused, and no summary issued; the merge and removal policies (S33, S42) still run |
| CHANGED | Each context's Tests required | all above | build | Unit and integration coverage for every edition guard; unlock and revoke round trips lose no data |
| CHANGED | Cross-cutting › Context boundaries | S49–S51 | build | App Store → Upgrade ACL; Upgrade → Matches, Players, Stats open host + published language (ADR-0011) |
| CHANGED | Cross-cutting › Layering | S49–S51 | build | StoreKit lives only in Upgrade's infrastructure adapter |
| CHANGED | Open questions › Q6 | — | — | Resolved by ADR-0006 (text tidy-up) |

---

# Context: Matches (Core)

## Match

**Business behaviours:** Start a live match from a setup at 0–0 with the match and frame-1 timers running; allow nothing but choosing the first breaker until one is chosen; award and remove frames, deriving the next breaker from the break rule; pause and resume (manually, and automatically on app shutdown); detect a set win and a match target and ask before ending; finish, abandon or cancel with confirmation, treating an early finish of a target style as abandonment unless finished anyway; flag stale matches on launch and resolve them; warn on long frames; correct ended matches without overwriting their history; turn abandoned into finished; delete ended matches; offer a temporary colour when both sides match. It must prevent: a player playing themselves, scoring while paused, timers changing on −, finished becoming abandoned, cancelled changing, invalid race-to corrections, exceeding the live-match limit — S1, S2, S4–S11, S15, S16, S25–S31, S37, S41, S43, S46, S47

### Value Objects
**Implementation skill:** `ddd-tactical-patterns`

- `MatchId` — opaque identifier; non-empty — S1, S2 — build
- `PlayerId` (Matches' reference to a Players `Player`) — opaque; non-empty — S1, S2 — build
- `Setup` — two `PlayerId`s (distinct; unordered for equality), `Game`, `MatchStyle`, `BreakRule`; equality = template identity — S1, S2, S12 — build
- `Game` — `pool` | `snooker` — S2, S20 — build
- `MatchStyle` — `mostFramesWins` | `raceTo(Target)` | `sets(sets: Target, frames: Target)` — S2, S15, S16, S21 — build
- `Target` — race to N, N ≥ 1; constructible from "race to N" or "best of M" with M odd (stored ⌈M/2⌉); remembers how it was entered for display; equality on N — S2, S21 — build
- `BreakRule` — `alternate` (default) | `winnerBreaks` — S2, S4, S21 — build
- `Side` — `PlayerId` + this match's display colour (may be a temporary override) — S1, S2, S46 — build
- `Frame` — winner `Side`, frame number, set number, length (`Duration?`; nil for a corrected-in frame), breaker — S5, S6, S29 — build
- `Score` — frames per side; for sets: sets won per side + current-set frames; displayed "(1) 5 – 2 (0)" — S5, S16 — build
- `Duration` (frame length / match length) — elapsed minus paused time; ≥ 0 — S5, S10, S28 — build
- `Result` — `win(Side)` | `draw` — S10, S31 — build
- `MatchStatus` — allowed transitions: AwaitingBreaker → InPlay | Paused | Finished | Abandoned | Cancelled; InPlay → InPlay | AwaitingConfirmation | Paused | Finished | Abandoned | Cancelled; AwaitingConfirmation → InPlay | Finished; Paused → InPlay | AwaitingBreaker | Finished | Abandoned | Cancelled; Abandoned → Finished | Deleted; Finished → Deleted; Cancelled → Deleted; no other — S4–S10, S15, S16, S25–S31 — build
- `StartTime` — full timestamp stored; day + time displayed ("Fri 19:30") — S2 — build
- `StaleResolution` — `resume` | `endAt(time)` | `endCapped` | `abandon` | `cancel` — S28 — build
- `ChosenEndTime` — last recorded action ≤ t ≤ now — S28 — build
- `CappedLength` — average length of past finished matches between the same two players on the same weekday, else 3 h — S28 — build
- `ScoreCorrection` — race to: exactly one side on the target; sets: per-set frame scores, inconsistencies produce warnings (not errors) — S29 — build

### Aggregate
**Implementation skill:** `ddd-tactical-patterns`

- Factory: `Match.start(setup, at:)` — guard: players distinct, targets valid; status AwaitingBreaker, score 0–0, match timer and frame-1 timer start at `at`; raises `MatchStarted` — S1, S2 — build
- Behaviour: `chooseBreaker(side)` — guard: AwaitingBreaker, not paused; → InPlay; raises `BreakerChosen` — S4 — build
- Behaviour: `correctBreaker(side)` — guard: live (InPlay or Paused); resets the break-rule origin; raises `BreakerCorrected` — S41 — build
- Behaviour: `awardFrame(side, at:)` — guard: InPlay; records frame length (frame start → `at`, minus paused); raises `FrameWon`; when a set target is reached also `SetWon`; when the match target is reached → AwaitingConfirmation and `MatchTargetReached` — S5, S15, S16, S47 — build
- Behaviour: `removeFrame(side)` — guard: side has ≥ 1 frame; InPlay or AwaitingConfirmation; removes that side's most recent frame; never touches timers; reverts a set win it caused; AwaitingConfirmation → InPlay; raises `FrameRemoved` — S6, S15, S16 — build
- Behaviour: `pause(at:)` — guard: AwaitingBreaker or InPlay; raises `MatchPaused` — S7, S47 — build
- Behaviour: `autoPause(at:)` — guard: AwaitingBreaker or InPlay; `at` not earlier than the last recorded action (may be earlier than now); raises `MatchAutoPaused` stamped with `at` — S27 — build
- Behaviour: `resume(at:)` — guard: Paused; → InPlay, or AwaitingBreaker if no breaker yet; raises `MatchResumed` — S8, S28, S47 — build
- Behaviour: `finish(at:, anyway:)` — guard: live; most frames wins any time (level = draw); target styles: allowed from AwaitingConfirmation, or short of target only with `anyway` (else error "will be abandoned"); end time = winning frame time when from AwaitingConfirmation; drops an in-progress frame; raises `MatchFinished` — S10, S15, S16, S28, S43 — build
- Behaviour: `abandon(at:)` — guard: live; raises `MatchAbandoned` — S25, S10, S28, S43 — build
- Behaviour: `cancel(at:)` — guard: live; raises `MatchCancelled` — S26, S28 — build
- Behaviour: `flagStale(now:)` — guard: live; last action ≥ 6 h ago; computes suggested end time and capped length (from Stats queries); raises `StaleMatchFlagged` — S28 — build
- Behaviour: `resolveStale(StaleResolution)` — delegates to resume / finish (with `ChosenEndTime` or `CappedLength`) / abandon / cancel — S28 — build
- Behaviour: `warnLongFrame(now:)` — guard: InPlay; current frame ≥ 30 min, then every 10 min; raises `LongFrameWarned` — S37 — build
- Behaviour: `overrideColour(side)` — guard: AwaitingBreaker; both sides share a colour; random different colour for one side, this match only; raises `MatchColourOverridden` — S46 — build
- Behaviour: `correctScore(ScoreCorrection)` — guard: Finished or Abandoned; recorded as a correction; raises `MatchScoreCorrected` — S29 — build [?] (Q1, Q2)
- Behaviour: `markFinished()` — guard: Abandoned; result = leader or draw; raises `MatchMarkedFinished` — S31 — build
- Behaviour: `delete()` — guard: Finished, Abandoned or Cancelled; raises `MatchDeleted` — S30, S42 — build
- Invariant: the two sides are different players — S2, S33 — build
- Invariant: next breaker is derived (alternate: origin breaks odd frames counted from the origin; winner breaks: last remaining frame's winner, else origin); sets don't affect it — S4, S5, S6, S41 — build
- Invariant: while Paused, only `resume`, `finish`, `abandon`, `cancel`, `correctBreaker` are allowed — S7 — build
- Invariant: an ended match's original events are never altered; corrections are new events — S29, S31 — build
- Invariant: only a stale match's length can be capped — S28 — build
- Invariant: a Paused match knows how it was paused (by hand: `MatchPaused`; automatically: `MatchAutoPaused`), for the edition guard on `ResumeMatch` — S7, S8, S27, S28 — build

### Domain Events
**Implementation skill:** `ddd-domain-events`

Stage 2 events are Matches' published language (ADR-0003), consumed by Stats; they are in-process in this single app, but their shape is a versioned contract.

- `MatchStarted` (incl. `Setup`, start time) — raised by `start`; Stage 2 (Stats; template policy; Live Activity) — S1, S2, S47 — build
- `BreakerChosen` — raised by `chooseBreaker`; Stage 2 (Stats; Live Activity) — S4 — build
- `BreakerCorrected` — raised by `correctBreaker`; Stage 2 (Stats; Live Activity) — S41 — build
- `FrameWon` — raised by `awardFrame`; Stage 2 (Stats; Live Activity) — S5 — build
- `SetWon` — raised by `awardFrame`; Stage 2 (Stats) — S16 — build
- `MatchTargetReached` — raised by `awardFrame`; Stage 2 (Stats) — S15, S16 — build
- `FrameRemoved` — raised by `removeFrame`; Stage 2 (Stats; Live Activity) — S6 — build
- `MatchPaused` — raised by `pause`; Stage 2 (Stats; Live Activity) — S7 — build
- `MatchAutoPaused` — raised by `autoPause`; Stage 2 (Stats; Live Activity) — S27 — build
- `MatchResumed` — raised by `resume`; Stage 2 (Stats; Live Activity) — S8 — build
- `MatchFinished` — raised by `finish`; Stage 2 (Stats; Live Activity) — S10 — build
- `MatchAbandoned` — raised by `abandon`; Stage 2 (Stats; Live Activity) — S25 — build
- `MatchCancelled` — raised by `cancel`; Stage 2 (Stats; Live Activity) — S26 — build
- `MatchScoreCorrected` — raised by `correctScore`; Stage 2 (Stats) — S29 — build
- `MatchMarkedFinished` — raised by `markFinished`; Stage 2 (Stats) — S31 — build
- `MatchDeleted` — raised by `delete`; Stage 2 (Stats) — S30, S42 — build
- `MatchColourOverridden` — raised by `overrideColour`; Stage 2 (Stats, per the Matches canvas) — S46 — build
- `LongFrameWarned` — raised by `warnLongFrame`; Stage 2 (iOS Notifications) — S37 — build
- `StaleMatchFlagged` — raised by `flagStale`; Stage 1 (drives the in-app prompt) — S28 — build

### Repository Port
**Implementation skill:** `ddd-repositories`

- `MatchRepository` — `getById`, `save` — S1–S10, S25–S31, S41, S46 — build
  - `findLive()` — live matches, oldest started first (ties by creation order): live list, limit check, finish all, auto-pause, stale check, long-frame timer, lock-screen match — S9, S11, S27, S28, S37, S43, S44, S47 — build
  - `findByPlayer(PlayerId)` — every match with that player: merge repointing, removal cascade — S33, S42 — build
  - `isAmongNewestEnded(MatchId, n)` — whether an ended match is among the n most recently ended (Free guard for corrections and deletions) — S17, S29, S30 — build

### Use Cases (command side)
**Implementation skill:** `ddd-application-layer`

- `StartMatch` — trigger: Scorer (template or details); guards: live-match limit (MatchSettings; **Free: 1**), "already in a live match" confirmation; **Free: style must be most frames wins and break rule alternate, else refused → upgrade offer (S52)**; reads `CurrentEdition` (Upgrade); load settings → `Match.start` → save → dispatch — S1, S2, S11, S44, S52 — build
- `ChooseBreaker` — trigger: Scorer — S4 — build
- `CorrectBreaker` — trigger: Scorer (match menu) — S41 — build
- `AwardFrame` — trigger: Scorer (in app or lock screen) — S5, S47 — build [?] (Q3, Q4)
- `RemoveFrame` — trigger: Scorer (−, or Undo on a prompt) — S6, S15, S16 — build [?] (Q4)
- `PauseMatch` / `ResumeMatch` — trigger: Scorer (in app or lock screen); `ResumeMatch` also from the stale prompt; **Free: `PauseMatch` refused → "Upgrade now" on the pause button (S52); `ResumeMatch` refused for a match paused by hand, allowed for one auto-paused after a kill** — S7, S8, S27, S28, S47, S52 — build
- `AutoPauseLiveMatches` — trigger: App lifecycle (launch, when the last session was killed rather than returned to the foreground); input: the last background time, if recorded (cleared on each return to the foreground); `findLive` → `autoPause(at:)` each running match, `at` = the later of the background time and that match's last action (the last action when no background time was recorded); already-paused matches untouched; runs before `FlagStaleMatches` — S27 — build
- `FinishMatch` — trigger: Scorer (menu + confirmation, or Finish prompt); early finish of a target style → returns "will be abandoned" unless `anyway` — S10, S15, S16 — build
- `AbandonMatch` — trigger: Scorer (menu + confirmation) — S25 — build
- `CancelMatch` — trigger: Scorer (menu + confirmation) — S26 — build
- `FinishAllMatches` — trigger: Scorer (live list + confirmation); finishable → `finish`, others → `abandon`, one dialog if any will be abandoned; **paid** (Free has one live match) — S43, S52 — build
- `FlagStaleMatches` — trigger: App lifecycle (launch); `findLive` filtered by idle ≥ 6 h; queries Stats for averages; prompts one at a time — S28 — build
- `ResolveStaleMatch` — trigger: Scorer's choice in the stale prompt — S28 — build
- `WarnLongFrame` — trigger: Clock (local notification schedule: 30 min, then every 10; rescheduled on `FrameWon`/`MatchResumed`, cancelled on pause or end) — S37 — build
- `OverrideMatchColour` — trigger: policy on `MatchStarted` when sides share a colour (Scorer accepts); **not offered while Free** (no colours shown) — S46 — build
- `CorrectMatchScore` — trigger: Scorer (timeline → Edit); **Free: only if `isAmongNewestEnded(id, 10)`** — S29 — build [?] (Q1, Q2)
- `MarkMatchFinished` — trigger: Scorer — S31 — build
- `DeleteMatch` — trigger: Scorer (swipe + confirmation); policy on `PlayerRemoved` (each of their matches); **Free: Scorer deletions only if `isAmongNewestEnded(id, 10)`; the S42 cascade is never limited** — S30, S42 — build
- `MovePlayerMatches` — trigger: policy on `PlayersMerged` (Players); repoints `PlayerId` in every match of the folded-in player, recorded as a correction — S33 — build
- `RemoveLiveActivityOnLock` — trigger: policy on `AppLocked` (Upgrade); removes the Live Activity; live matches carry on unchanged (style, break rule, pauses kept) — S47, S51 — build

### Read Requirements (query side)
**Implementation skill:** `ddd-cqrs`

- `LiveMatches` — fields: match id, players, colours, score, match timer, paused; oldest started first; bypasses the domain model; colours omitted while Free — S9, S11, S43 — build
- `LiveMatchScreen` — fields: day + time, sides with colours, score (sets format), breaker dot, match timer, frame timer, paused, available controls, head-to-head (from Stats); **Free:** no colours, head-to-head greyed with an upgrade prompt, pause button shows "Upgrade now" — S1, S2, S4–S8, S14, S16, S22, S52 — build
- `LockScreenState` — **Unlocked only (none while Free)**; the oldest live match (as `findLive`), none if no live match; fields: match id, sides, score, breaker, frame timer, paused; moves to the next-oldest when the shown match is finished, abandoned or cancelled — S47 — build [?] (Q4)
- `IsPlayerInLiveMatch(PlayerId)` — open host for Players' archive guard; also the "are you sure" check on start — S11, S34 — build
- `HavePlayedEachOther(PlayerId, PlayerId)` — open host for Players' merge guard — S33 — build

### Persistence note
Event-sourced: **yes** — the business owner decided that a match's in-game actions are events on its stream and post-end changes are alterations (ADR-0006). **Implementation skill:** `ddd-event-sourcing`

### Tests required
**Implementation skill:** `ddd-testing`

- Domain unit: every behaviour and guard above (each allowed and each refused transition of `MatchStatus`); `autoPause` refuses a time before the last action; `Target` (best of odd only, ⌈M/2⌉, display); `Setup` equality (unordered players, best-of = race-to); breaker derivation (alternate, winner breaks, after −, after correction, across sets); frame length minus paused time; − leaves timers alone; set win and its revert; early finish of target styles; end time = winning frame time; draws; stale detection at 6 h; `ChosenEndTime` bounds; capped length fallback 3 h; long-frame thresholds 30/10; race-to correction validity; sets correction warnings; abandoned → finished only
- Integration: one per use case and read requirement above, including the live-match limit, finish all with mixed matches, auto-pause after a kill (at the background time; at a later lock-screen action when there is one; at the last action when the app was on screen; never on backgrounding), auto-pause before the stale check, lock-screen hand-over to the next-oldest live match, stale prompt order
- Edition (ADR-0010): unit — the pause-kind invariant; integration — Free refuses a 2nd live match, other styles and break rules, manual pause, resuming a manual pause, corrections and deletions beyond the newest 10; Free allows auto-pause and its resume; `AppLocked` removes the Live Activity and leaves live matches unchanged

---

## Template

**Business behaviours:** Every new setup becomes a template as soon as its match starts; a known setup's use count goes up; listed most used first; delete by swipe; a deleted template comes back (use count restarting) when the setup is played again; merging players combines templates that become identical; removing a player deletes their templates; templates with an archived player are hidden — S1, S2, S12, S33, S34, S36, S42

### Value Objects
**Implementation skill:** `ddd-tactical-patterns`

- `TemplateId` — opaque; non-empty — S12 — build
- `Setup` — shared with `Match` (above); the template's identity — S12 — build
- `UseCount` — integer ≥ 1 — S1, S12 — build

### Aggregate
**Implementation skill:** `ddd-tactical-patterns`

- Factory: `Template.create(setup)` — use count 1; raises `TemplateCreated` — S12 — build
- Behaviour: `recordUse()` — use count +1; raises `TemplateUsed` — S1, S12 — build
- Behaviour: `combine(with:)` — absorbs an identical template after a merge; use counts add; the absorbed one is deleted; raises `TemplatesCombined` — S33 — build
- Behaviour: `delete()` — raises `TemplateDeleted` — S36, S42 — build
- Invariant: at most one active template per `Setup` — S12, S33 — build

### Domain Events
**Implementation skill:** `ddd-domain-events`

- `TemplateCreated` — raised by `create`; Stage 1 — S12 — build
- `TemplateUsed` — raised by `recordUse`; Stage 1 — S12 — build
- `TemplatesCombined` — raised by `combine`; Stage 1 — S33 — build
- `TemplateDeleted` — raised by `delete`; Stage 1 — S36, S42 — build

### Repository Port
**Implementation skill:** `ddd-repositories`

- `TemplateRepository` — `getById`, `save` — S12, S36 — build
  - `findBySetup(Setup)` — create-or-use on `MatchStarted` — S12 — build
  - `findByPlayer(PlayerId)` — merge combining, removal cascade — S33, S42 — build

### Use Cases (command side)
**Implementation skill:** `ddd-application-layer`

- `CreateOrUseTemplate` — trigger: policy on `MatchStarted`; `findBySetup` → `create` or `recordUse` → save; runs whatever the edition (silently while Free) — S1, S2, S12 — build
- `DeleteTemplate` — trigger: Scorer (swipe); policy on `PlayerRemoved`; **Free: Scorer deletion refused; the S42 cascade is never limited** — S36, S42 — build
- `CombineTemplatesAfterMerge` — trigger: policy on `PlayersMerged` — S33 — build

### Read Requirements (query side)
**Implementation skill:** `ddd-cqrs`

- `TemplateList` — fields: template id, players (names, colours), game, style + targets as entered, break rule, use count; most used first; excludes templates with an archived player; empty list → New Match opens the details screen directly; **Free: replaced by an "Upgrade now" prompt in place** — S1, S2, S34, S52 — build

### Persistence note
Event-sourced: no

### Tests required
**Implementation skill:** `ddd-testing`

- Domain unit: create, recordUse, combine (counts add), delete; one-per-setup
- Integration: create-or-use on start, deleted template recreated with count 1, merge combining, list ordering and archived hiding, empty list routing; templates recorded while Free appear on unlock; Free refuses deletion and shows the prompt

---

## MatchSettings

**Business behaviours:** Holds the defaults for starting a match (game, style with targets, break rule) and the live-match limit; changes affect only matches started afterwards. Value-only per device; raises nothing (ADR-0002 split it from the baseline's `Preferences`) — S2, S11, S20, S21, S44

### Value Objects
**Implementation skill:** `ddd-tactical-patterns`

- `MatchDefaults` — `Game` (pool), `MatchStyle` (mostFramesWins), `BreakRule` (alternate) — S2, S20, S21 — build
- `LiveMatchLimit` — 1…100, default 10; effective limit 1 while Free, whatever is stored — S11, S44 — build

### Aggregate
**Implementation skill:** `ddd-tactical-patterns`

- Factory: `MatchSettings.initial` — the defaults above — S20, S21, S44 — build
- Behaviour: `changeDefaults(game?, style?, breakRule?)` — guard: valid targets; raises nothing — S20, S21 — build
- Behaviour: `setLiveMatchLimit(n)` — guard: 1…100; raises nothing — S44 — build

### Domain Events
None (settings; no undo case).

### Repository Port
**Implementation skill:** `ddd-repositories`

- `MatchSettingsStore` — `get`, `save` (single per device) — S20, S21, S44 — build

### Use Cases (command side)
**Implementation skill:** `ddd-application-layer`

- `ChangeMatchDefaults` — trigger: Scorer (settings); **Free: style and break-rule changes refused; the game (S20) stays free** — S20, S21 — build
- `SetLiveMatchLimit` — trigger: Scorer (settings); **paid** — S44, S52 — build

### Read Requirements (query side)
**Implementation skill:** `ddd-cqrs`

- `MatchSettingsView` — fields: game, style + targets, break rule, limit — S2, S20, S21, S44 — build

### Persistence note
Event-sourced: no

### Tests required
**Implementation skill:** `ddd-testing`

- Domain unit: initial defaults, limit bounds, invalid targets refused
- Integration: defaults applied to the details screen; limit enforced by `StartMatch`; Free uses limit 1 and the Free defaults

---

# Context: Players (Supporting)

## Player

**Business behaviours:** Create a player with a unique, case-insensitive name and the next unused palette colour; rename (unique); change colour (repeats allowed); merge two records of the same person unless they ever played each other; archive (refused while in a live match) and unarchive; remove an archived player permanently, cascading to their matches, templates and series. Archived names are blocked except via removal — S2, S3, S22, S32, S33, S34, S35, S42, S48

### Value Objects
**Implementation skill:** `ddd-tactical-patterns`

- `PlayerId` — opaque; non-empty — S3 — build
- `PlayerName` — non-blank; compared case-insensitively — S3, S32, S48 — build
- `Colour` — a palette colour; not unique — S3, S22 — build
- `Palette` — ordered colours; next unused, repeating from the start when exhausted — S3 — build
- `PlayerStatus` — allowed transitions: Active → Archived | MergedAway; Archived → Active | Removed; no other — S33, S34, S35, S42 — build

### Aggregate
**Implementation skill:** `ddd-tactical-patterns`

- Factory: `Player.add(name, colour)` — guard: name unique among all players (active or archived); raises `PlayerAdded` — S3, S48 — build
- Behaviour: `rename(name)` — guard: unique; not an archived player's name; raises `PlayerRenamed` — S32 — build
- Behaviour: `changeColour(colour)` — raises `PlayerColourChanged` — S22 — build
- Behaviour: `mergeInto(kept)` — guard: both active; never played each other (Matches query); → MergedAway; raises `PlayersMerged` — S33 — build
- Behaviour: `archive()` — guard: Active; not in a live match (Matches query); raises `PlayerArchived` — S34 — build
- Behaviour: `unarchive()` — guard: Archived; raises `PlayerUnarchived` — S35 — build
- Behaviour: `remove()` — guard: Archived; raises `PlayerRemoved` — S42 — build
- Invariant: player names are unique case-insensitively across active and archived players — S3, S32 — build

### Domain Events
**Implementation skill:** `ddd-domain-events`

- `PlayerAdded` — raised by `add`; Stage 2 (Stats) — S3, S48 — build
- `PlayerRenamed` — raised by `rename`; Stage 2 (Stats) — S32 — build
- `PlayerColourChanged` — raised by `changeColour`; Stage 2 (Matches display, Stats) — S22 — build
- `PlayersMerged` — raised by `mergeInto`; Stage 2 (Matches, Stats; Me policy) — S33 — build
- `PlayerArchived` — raised by `archive`; Stage 2 (Stats filters, Matches template list) — S34 — build
- `PlayerUnarchived` — raised by `unarchive`; Stage 2 (Stats, Matches) — S35 — build
- `PlayerRemoved` — raised by `remove`; Stage 2 (Matches, Stats; Me policy) — S42 — build

### Repository Port
**Implementation skill:** `ddd-repositories`

- `PlayerRepository` — `getById`, `save` — S3, S22, S32–S35, S42 — build
  - `findByName(PlayerName)` — case-insensitive, including archived — S2, S3, S32 — build
  - `nextUnusedColour()` — from colours of existing players — S3 — build
  - `countActive()` — active players only (archived, merged away, removed excluded): Free cap — S3, S35 — build

### Use Cases (command side)
**Implementation skill:** `ddd-application-layer`

- `AddPlayer` — trigger: Scorer (new name on the details screen, welcome); archived name → error offering `RemovePlayer`; **Free: refused when `countActive()` ≥ 5 → upgrade offer** — S2, S3, S48, S52 — build
- `RenamePlayer` — trigger: Scorer (settings) — S32 — build
- `ChangePlayerColour` — trigger: Scorer (settings); **paid** — S22, S52 — build
- `MergePlayers` — trigger: Scorer (settings); asks Matches `HavePlayedEachOther` — S33 — build
- `ArchivePlayer` — trigger: Scorer (settings); asks Matches `IsPlayerInLiveMatch` — S34 — build
- `UnarchivePlayer` — trigger: Scorer (settings); **Free: refused when `countActive()` ≥ 5 → upgrade offer** — S35, S52 — build
- `RemovePlayer` — trigger: Scorer (settings, or the offer from S2/S3/S32) + confirmation — S42 — build

### Read Requirements (query side)
**Implementation skill:** `ddd-cqrs`

- `PlayerSuggestions(prefix)` — fields: id, name, colour; active players only, case-insensitive prefix match; colour omitted while Free — S2, S3 — build
- `PlayersList` — fields: id, name, colour, status; active and archived sections; colour omitted while Free — S22, S32–S35, S42 — build

### Persistence note
Event-sourced: no

### Tests required
**Implementation skill:** `ddd-testing`

- Domain unit: name uniqueness case-insensitive; archived-name block; palette next/repeat; every `PlayerStatus` transition allowed and refused
- Integration: merge refused when they played each other; archive refused while in a live match; removal cascades (matches, templates, series, Me); Free cap of 5 active (archived excluded, Me included) on add and unarchive; players over the cap after a revocation stay

---

## MeSetting

**Business behaviours:** Marks which player is "Me" on this device, shown "Me (Callum)"; optional; set from the welcome, the main menu or settings; follows the kept player on a merge; cleared when that player is removed. Value-only per device; raises nothing — S18, S19, S33, S38, S42, S45, S48

### Value Objects
**Implementation skill:** `ddd-tactical-patterns`

- `Me` — optional `PlayerId` — S45 — build

### Aggregate
**Implementation skill:** `ddd-tactical-patterns`

- Behaviour: `set(PlayerId)` / `clear()` — raises nothing — S45, S48, S42 — build

### Domain Events
None.

### Repository Port
**Implementation skill:** `ddd-repositories`

- `MeSettingStore` — `get`, `save` (single per device) — S45 — build

### Use Cases (command side)
**Implementation skill:** `ddd-application-layer`

- `SetMe` — trigger: Scorer (welcome, main menu, settings) — S45, S48 — build
- `UpdateMeOnMerge` — trigger: policy on `PlayersMerged` — S33 — build
- `ClearMeOnRemoval` — trigger: policy on `PlayerRemoved` — S42 — build

### Read Requirements (query side)
**Implementation skill:** `ddd-cqrs`

- `WhoAmI` — fields: player id, name ("Me (Callum)"); used by Stats — S18, S19, S38, S45 — build
- `Welcome` — first launch: name entry, then a skippable, replayable walkthrough — S48 — build

### Persistence note
Event-sourced: no

### Tests required
**Implementation skill:** `ddd-testing`

- Integration: set, follow on merge, clear on removal; welcome creates the player and sets Me

---

# Context: Stats (Core)

## Series

**Business behaviours:** A named group of setups (a setup can be in several); every past and future match with one of its setups belongs to it; rename, add or remove setups, delete (never touches matches); a monthly summary on the 1st for each series with matches last month; follows player merges and removals — S33, S38, S39, S40, S42

### Value Objects
**Implementation skill:** `ddd-tactical-patterns`

- `SeriesId` — opaque; non-empty — S39 — build
- `SeriesName` — non-blank — S39, S40 — build
- `Setup` — as published in `MatchStarted` (Matches' published language, conformist) — S39 — build
- `Month` — calendar month — S38 — build

### Aggregate
**Implementation skill:** `ddd-tactical-patterns`

- Factory: `Series.create(name, setups)` — guard: name non-blank; raises `SeriesCreated` — S39 — build
- Behaviour: `change(name?, add:, remove:)` — raises `SeriesChanged` — S40, S33, S42 — build
- Behaviour: `delete()` — raises `SeriesDeleted` — S40 — build
- Behaviour: `issueSummary(month)` — guard: at least one match of its setups in that month; raises `SeriesSummaryIssued` — S38 — build [?] (Q5)

### Domain Events
**Implementation skill:** `ddd-domain-events`

- `SeriesCreated` — raised by `create`; Stage 1 — S39 — build
- `SeriesChanged` — raised by `change`; Stage 1 — S40, S33, S42 — build
- `SeriesDeleted` — raised by `delete`; Stage 1 — S40 — build
- `SeriesSummaryIssued` — raised by `issueSummary`; Stage 2 (iOS Notifications) — S38 — build

### Repository Port
**Implementation skill:** `ddd-repositories`

- `SeriesRepository` — `getById`, `save` — S39, S40 — build
  - `findAll()` — monthly summaries — S38 — build
  - `findContainingPlayer(PlayerId)` — merge repointing, removal — S33, S42 — build

### Use Cases (command side)
**Implementation skill:** `ddd-application-layer`

- `CreateSeries` — trigger: Scorer (Series screen); **paid** — S39, S52 — build
- `ChangeSeries` / `DeleteSeries` — trigger: Scorer (Series screen); **paid** — S40, S52 — build
- `RepointSeriesOnMerge` — trigger: policy on `PlayersMerged` — S33 — build
- `RemovePlayerFromSeries` — trigger: policy on `PlayerRemoved` — S42 — build
- `IssueMonthlySummaries` — trigger: Clock (1st of the month, for the previous month); **skipped while Free** — S38 — build [?] (Q5)

### Read Requirements (query side)
**Implementation skill:** `ddd-cqrs`

- `SeriesList` — fields: id, name, setups; locked while Free — S39, S40, S52 — build
- `MonthlySummary(series, month)` — fields: per-pairing (or "you" when Me is in the series) matches W–D–L, frames, deciders; change since the previous month — S38 — build

### Persistence note
Event-sourced: no

### Tests required
**Implementation skill:** `ddd-testing`

- Domain unit: create, change, delete, summary guard
- Integration: membership by setup (past and future), several series per setup, merge/removal policies, summary only for series with matches, "you" vs per-pairing; Free refuses series commands and issues no summary, while merge and removal policies still run

---

## Stats read models (built from published events)

Projections over Matches' and Players' published events (ADR-0003). No aggregate; bypass the domain model. **Implementation skill:** `ddd-cqrs`

- `MatchRecord` projection — from all Stage 2 match events: result (win/draw), status (finished/abandoned/cancelled), sides, setup, start/end, length, frames, corrections; rebuilt on `MatchScoreCorrected`, `MatchMarkedFinished`; removed on `MatchDeleted` — S10, S17, S25, S26, S29, S30, S31 — build
- `PastMatches` — fields: day + time, players, score, style, finished/abandoned; newest first; filters: show cancelled, include archived players; **Free: the newest 10 ended matches plus a count of hidden ones (tapping it opens the upgrade offer); all on unlock** — S17, S52 — build
- `MatchTimeline` — fields: per frame: winner, frame time, match time at that point, running score; corrections marked; Free: only for the visible matches — S17 — build
- `HeadToHead(PlayerId, PlayerId)` — open host for Matches' live screen; fields: Matches W–D–L, Frames, Deciders (only when non-zero); all finished matches, any game, any style; **locked while Free** (returns no figures) — S14 — build
- `Stats(filter)` — groups: opponent, weekday (combinable); filters: opponent, weekday, game, style, series, date range, include abandoned, include archived players; fields: matches W–D–L, frames won–lost, deciders, match deciders, set deciders, win %, average frame time; point of view: Me or a chosen player; **locked while Free** — S18, S19, S52 — build
- `Deciders` computation — decider: frame won from level at the end of a set or frames-style match, any set; match decider: such a frame that is the match's last (also a decider); set decider: deciding set with sets level (own tally, never a match decider) — S10, S14, S18 — build
- `AverageFrameTime(PlayerId)` — open host for Matches' stale prompt — S28 — build
- `AverageMatchLength(players, weekday)` — finished matches only; nil when none (Matches falls back to 3 h) — S28 — build

### Tests required
**Implementation skill:** `ddd-testing`

- Domain unit (pure functions): decider rules with the worked examples (3–1 / 9–8 → match decider; 3–2 / 9–5 → set decider only; 3–2 / 9–8 → both; earlier-set 9–8 → decider only); W–D–L with draws; inclusion rules (finished only by default; abandoned opt-in; cancelled never; archived opt-in)
- Integration: projections rebuilt correctly after corrections and deletions; head-to-head excludes the live match; projections keep building while Free; Free shows the newest 10 and locks head-to-head and stats; unlock shows everything with no rebuild

---

# Context: Upgrade (Generic)

## Edition

**Business behaviours:** Know whether this device is Free or Unlocked. Unlock it only after the App Store verifies the one-off purchase, whether now, after an Ask to Buy approval (even after a restart), or through a restore. Return it to Free when the App Store revokes the purchase. Serve the edition and the Free limits to the other contexts from a local cache that offline never re-locks. Sell the upgrade with an offer in place (templates, pause), a generic screen for other paid features, and a benefits menu item shown only while Free.
It must prevent: unlocking without a verified purchase; re-locking because the device is offline; showing the offer on launch or as a repeated pop-up; deleting or rewriting any other context's data — S49, S50, S51, S52, S53

### Value Objects
**Implementation skill:** `ddd-tactical-patterns`

- `EditionStatus` — `free` (initial) | `unlocked`; allowed transitions: free → unlocked; unlocked → free; no other — S49, S50, S51 — build
- `FreeLimits` — live matches 1; active players 5; visible ended matches 10; allowed styles {most frames wins}; allowed break rules {alternate}; one table, owned here (ADR-0011) — S1–S3, S11, S17, S21, S29, S30, S35, S44 — build
- `PaidFeature` — templates, manualPause, raceTo, sets, winnerBreaks, extraPlayers, fullHistory, colours, headToHead, stats, series, severalLiveMatches, lockScreen — S1, S7, S8, S11, S14–S19, S21, S22, S36, S38–S40, S43, S44, S46, S47, S52, S53 — build
- `UnlockProductId` — the single non-consumable product identifier — S49, S50 — build

### Aggregate
**Implementation skill:** `ddd-tactical-patterns`

- Factory: `Edition.initial` — status free — S49 — build
- Behaviour: `unlock()` — guard: free (idempotent when already unlocked: no event); called only with a verified purchase from the adapter; raises `AppUnlocked` — S49, S50 — build
- Behaviour: `lock()` — guard: unlocked (idempotent when free: no event); raises `AppLocked` — S51 — build
- Query: `allows(PaidFeature) -> Bool`, `limits -> FreeLimits?` (nil when unlocked) — S52 and every guarded scenario — build
- Invariant: the status changes only through `unlock` and `lock`, never because a check failed or the device is offline — S49, S51 — build

### Domain Events
**Implementation skill:** `ddd-domain-events`

Stage 2 events are Upgrade's published language (ADR-0011), consumed by Matches, Players and Stats; in-process, versioned shape.

- `AppUnlocked` — raised by `unlock`; Stage 2 (Matches, Players, Stats; benefits menu item hidden) — S49, S50, S53 — build
- `AppLocked` — raised by `lock`; Stage 2 (Matches removes the Live Activity; benefits menu item shown) — S51, S53, S47 — build

### Repository Port
**Implementation skill:** `ddd-repositories`

- `EditionStore` — `get`, `save` (single per device, cached locally; survives offline launches) — S49, S50, S51 — build
- `AppStorePort` — `purchase(UnlockProductId) -> purchased | pending | cancelled | failed`, `restore() -> unlockOnRecord: Bool`, `transactionUpdates` (verified, revoked) — S49, S50, S51 — build

### Use Cases (command side)
**Implementation skill:** `ddd-application-layer`

- `PurchaseUnlock` — trigger: Scorer (Buy on the offer or benefits screen); `AppStorePort.purchase` → purchased: `unlock` → save → dispatch; pending: nothing yet (an approval later arrives through `HandleAppStoreUpdate`); cancelled or failed: nothing changes — S49, S52, S53 — build
- `RestorePurchases` — trigger: Scorer (Restore link); unlock on record → `unlock`; none → "Nothing to restore" — S50 — build
- `HandleAppStoreUpdate` — trigger: App Store transaction updates at launch and while running (via ACL); verified unlock → `unlock`; revocation → `lock`; save → dispatch — S49, S51 — build
- `ShowUpgradeOffer(PaidFeature)` — trigger: a refused guard in Matches, Players or Stats, or a tap on a paid feature; in place for templates and pause, the generic screen otherwise; raises nothing — S52 — build

### Read Requirements (query side)
**Implementation skill:** `ddd-cqrs`

- `CurrentEdition` — open host for Matches, Players, Stats; fields: status, `FreeLimits` (when free), `allows(PaidFeature)`; served from `EditionStore`, never waits on the App Store — S1–S3, S7, S8, S11, S14–S19, S21, S22, S29, S30, S35, S36, S38–S40, S43, S44, S46, S47, S52 — build
- `BenefitsScreen` — fields: the list of paid features in plain language, price (from the App Store, localised), Buy, Restore; shown only while free; the menu item is visible only while free — S52, S53 — build

### Persistence note
Event-sourced: no

### Tests required
**Implementation skill:** `ddd-testing`

- Domain unit: `EditionStatus` transitions allowed and refused; `unlock` and `lock` idempotency; `allows` for every `PaidFeature` in both editions; `FreeLimits` values
- Integration (fake `AppStorePort`): purchase purchased, pending then approved later (including after a restart), cancelled and failed; restore with and without a purchase on record; revocation → `AppLocked`; offline launch keeps the cached edition; benefits menu item hidden on `AppUnlocked` and shown on `AppLocked`; an unlock then revoke round trip deletes no match, player, template or series

---

# Cross-cutting

## Layering
**Implementation skill:** `ddd-project-structure`

- Per context: domain (no dependencies: no SwiftUI, SwiftData/Core Data, ActivityKit, UserNotifications), application (use cases and ports), infrastructure (persistence, iOS adapters), presentation (SwiftUI). Dependency rule enforced by Swift package / module boundaries — all contexts — build
- Contexts are separate modules; a context depends on another only through its published events and open-host queries — all — build
- StoreKit appears only in Upgrade's infrastructure adapter (`AppStorePort`); the Matches, Players and Stats domains see only `CurrentEdition`, `AppUnlocked`, `AppLocked` — S49–S51 — build

## Context boundaries (from strategic design)
- Players → Matches: Customer/Supplier (names, colours, player events) — ADR-0002
- Matches → Players: Open host service (`IsPlayerInLiveMatch`, `HavePlayedEachOther`) — ADR-0002
- Matches → Stats: Published language, Stats conformist (all Stage 2 match events) — ADR-0003
- Players → Stats: Published language, Stats conformist (player events, `WhoAmI`) — ADR-0003
- Stats → Matches: Open host service (`HeadToHead`, `AverageFrameTime`, `AverageMatchLength`) — ADR-0003
- App Store → Upgrade: Anti-corruption layer (StoreKit transactions, Ask to Buy approvals, revocations → `unlock` / `lock`) — ADR-0011
- Upgrade → Matches, Players, Stats: Open host service + published language, downstream conformist (`CurrentEdition`; `AppUnlocked`, `AppLocked`); each downstream enforces `FreeLimits` on its own data — ADR-0011
- Matches, Stats → iOS: Anti-corruption layer — adapters for UserNotifications (S37, S38), ActivityKit Live Activities + App Intents for lock-screen buttons (S47), app lifecycle launch signals, incl. kill detection and the last background time (S27, S28); no iOS types inside a domain — build

## Design-for-later constraints (from decisions.md)
- A `Frame` must be extensible with a loss reason (S23, later) and a snooker points breakdown by colour without remodelling — Matches — build
- A match's event history must be able to accept events from more than one device (shared matches, later) — Matches — build
- All saved state must be uploadable in full (S24, later): persistence must allow exporting every match's full history and all players, templates, series and settings — all — build
- Free limits never delete or rewrite data: hidden matches, unshown colours and silently recorded templates must all be intact on unlock — all — build (ADR-0010)

## Open questions blocking items
All deferred by the business owner to implementation; they do not block the MVP.

| Q | Item | Scenario | Owner |
|---|------|----------|-------|
| Q1 | `Match.correctScore` — phone dies mid-correction | S29 | Business owner |
| Q2 | `Match.correctScore` — two corrections in a row | S29 | Business owner |
| Q3 | `AwardFrame` — + while a Finish/Continue prompt shows | S5, S15, S16 | Business owner |
| Q4 | `AwardFrame` / `RemoveFrame` / `LockScreenState` — simultaneous lock-screen + and in-app − | S6, S47 | Business owner |
| Q5 | `Series.issueSummary` — match ending during summary | S38 | Business owner |
| ~~Q6~~ | `Match` persistence — resolved by ADR-0006 | S1–S31 | — |
