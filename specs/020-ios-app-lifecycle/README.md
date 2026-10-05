---
status: planned
created: 2026-10-05
priority: medium
tags:
- ios
- infrastructure
depends_on:
- '15'
parent: '1'
created_at: 2026-10-05T10:42:31.524838Z
updated_at: 2026-10-05T10:42:31.524838Z
---

# iOS app lifecycle adapter

## Overview
An app lifecycle anti-corruption adapter: auto-pause after the app is killed (S27) and the stale-match check on launch (S28). Source: `docs/ddd-requirements.md` › Cross-cutting › Context boundaries, `AutoPauseLiveMatches` (ADR-0004, ADR-0005).

## Requirements
- [ ] Going to the background (switching apps, locking the phone) never pauses: matches keep running and stay scoreable from the lock screen (S47)
- [ ] Record the time the app goes to the background; clear it on every return to the foreground
- [ ] On launch, detect that the last session was killed (it never returned to the foreground cleanly). iOS gives no reliable termination signal for a suspended app, so detection happens here, not in `willTerminate`.
- [ ] After a kill, invoke `AutoPauseLiveMatches` with the recorded background time (or none). The use case pauses each match at the later of that time and its last action.
- [ ] Then invoke `FlagStaleMatches` and present the stale prompt one match at a time, sending the choice to `ResolveStaleMatch`
- [ ] No lifecycle types leak into the application or domain layers

## UI (design language: 022)
- [ ] The **stale prompt** is a system alert or sheet, one match at a time:
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
