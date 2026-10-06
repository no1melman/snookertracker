---
status: complete
created: 2026-10-05
priority: medium
tags:
- ios
- infrastructure
depends_on:
- '15'
parent: '1'
created_at: 2026-10-05T10:42:31.524838Z
updated_at: 2026-10-06T20:13:15.193875Z
completed_at: 2026-10-06T20:13:15.193875Z
transitions:
- status: in-progress
  at: 2026-10-05T20:46:01.144353Z
- status: complete
  at: 2026-10-06T20:13:15.193875Z
---

# iOS app lifecycle adapter

## Overview
An app lifecycle anti-corruption adapter: auto-pause after the app is killed (S27) and the stale-match check on launch (S28). Source: `docs/ddd-requirements.md` › Cross-cutting › Context boundaries, `AutoPauseLiveMatches` (ADR-0004, ADR-0005).

## Requirements
- [x] Going to the background (switching apps, locking the phone) never pauses: matches keep running and stay scoreable from the lock screen (S47)
- [x] Record the time the app goes to the background; clear it on every return to the foreground
- [x] On launch, detect that the last session was killed (it never returned to the foreground cleanly). iOS gives no reliable termination signal for a suspended app, so detection happens here, not in `willTerminate`.
- [x] After a kill, invoke `AutoPauseLiveMatches` with the recorded background time (or none). The use case pauses each match at the later of that time and its last action.
- [x] Then invoke `FlagStaleMatches` and present the stale prompt one match at a time, sending the choice to `ResolveStaleMatch`
  - `AppLaunchSequence` `afterAutoPause` calls `StaleMatchQueue.flag()`.
- [x] No lifecycle types leak into the application or domain layers

## UI (design language: 022)
- [x] The **stale prompt** is a system alert or sheet, one match at a time:
  - `.stalePrompt(...)` on the hub in `AppRoot`, hidden while Welcome shows.
  - It shows the players, the score and how long the match has been idle
  - Its options are the choices `ResolveStaleMatch` offers

## Non-goals
- Background task scheduling beyond the above
- Computing the pause time (the `AutoPauseLiveMatches` use case, spec 015)

## Acceptance criteria
- Integration tests:
  - A kill while in the background, then a relaunch, pauses each running match at the background time
  - A lock-screen frame after backgrounding, then a kill, pauses at that frame's time
  - A kill while on screen (no background time) pauses at each match's last action
  - Going to the background and returning leaves live matches running
  - Auto-pause runs before the stale check; a match idle ≥ 6 h is then prompted for
- Checked manually on the simulator

**Implementation skill:** `ddd-application-layer` (ports) · **Tests:** `ddd-testing`

## Progress
- **Done (S27):** `AutoPauseLiveMatches` + `AppLifecycle` adapter (UserDefaults markers) + `AppLaunchSequence`, run before live matches load. Pause time per ADR-0005. Launches that iOS makes in the background for a lock-screen button skip auto-pause (ADR-0007). Tests: `AutoPauseLiveMatchesTests`, `AppLifecycleTests`.
- **Remains (S28):** `FlagStaleMatches` and the stale prompt plug into `afterAutoPause` in `AppContainer`, once Stats averages exist (014/015).

## Progress (2026-10-06)
- Verified: ticked the first four items and the no-leak item. `AppLifecycle` records the background time on `.background`, clears it on `.active`, detects a kill on the next launch and `AppLaunchSequence` calls `autoPauseLiveMatches` before the `afterAutoPause` steps. Lifecycle types live only in `Shared/iOSAdapters`, and `AppLifecycleTests` (7) cover the kill and background cases. Open: `FlagStaleMatches` and the stale prompt, and the S28 integration test.

## Progress (S28)
- `StaleMatchQueue` (`@Observable`, `Matches/Application/Stale/`) holds the prompts: `flag()` runs `FlagStaleMatches`, `current` is the match being asked about, `resolve(choice, anyway:)` runs `ResolveStaleMatch` and moves on. A match played or ended meanwhile is skipped quietly; any other refusal keeps it.
- `.stalePrompt(queue)` presents `current` as a sheet that can't be swiped away: players and score, idle time, Ran and Capped side by side (with where the cap comes from), Resume, End at a time (picker bounded by the last action and the flag time, starting at the suggestion), End with capped length, Abandon and Cancel (with the live screen's confirmations; hidden while awaiting a target confirmation). Short of the target asks "Finish Anyway".
- Left: wire `queue.flag()` into `afterAutoPause` and `.stalePrompt` into `AppRoot`; the "auto-pause runs before the stale check" integration test (needs `AppLifecycleTests` + the Stale use cases); checking on the simulator.
