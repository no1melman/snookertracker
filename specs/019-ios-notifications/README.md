---
status: complete
created: 2026-10-05
priority: medium
tags:
- ios
- infrastructure
depends_on:
- '15'
- '17'
parent: '1'
created_at: 2026-10-05T10:42:31.520822Z
updated_at: 2026-10-06T20:13:14.973344Z
completed_at: 2026-10-06T20:13:14.973344Z
transitions:
- status: in-progress
  at: 2026-10-06T20:10:25.229664Z
- status: complete
  at: 2026-10-06T20:13:14.973344Z
---

# iOS notifications adapter

## Overview
A UserNotifications anti-corruption adapter for the long-frame warnings (S37) and the monthly series summaries (S38). Source: `docs/ddd-requirements.md` › Cross-cutting › Context boundaries, and `WarnLongFrame`.

## Requirements
- [x] A UserNotifications adapter in infrastructure for the `NotificationScheduler` port defined in 015: `UserNotificationsScheduler` (`Sources/Shared/iOSAdapters`)
- [x] Long frame: schedule local notifications at 30 min, then every 10 min. Reschedule on `FrameWon` or `MatchResumed`; cancel on a pause or the end of the match. Thresholds are fixed (not configurable).
- [x] Monthly summary: deliver `SeriesSummaryIssued` as a notification on the 1st (017 adapts its own port to the adapter's generic `deliver(title:body:at:id:)`)
  - `AppContainer` subscribes to `SeriesSummaryIssuedPublished` and calls `deliver`; `IssueMonthlySummaries` runs at launch and on every foreground.
- [x] Ask for notification permission at a sensible point (not on first launch before the welcome): `requestAuthorization()`, called when the first match starts
- [x] Composition-root wiring (below) and the simulator check
  - Wired in `AppContainer`; permission is asked on the first `MatchStarted`. Simulator shows the prompt; a fired warning is not yet checked by hand.

## Design
- Warnings must fire while the app is suspended, so the `WarnLongFrame` policy (Matches Application, `Notifications/`) hands the OS a batch of 12 one-off notifications per match (30, 40, …, 140 min of frame time) instead of running a timer. iOS keeps at most 64 pending per app.
- The policy reads the live-match read model (projected before dispatch). `MatchStarted`, `BreakerChosen`, `FrameWon`, `FrameRemoved`, `MatchResumed`, `MatchTargetReached` reschedule from the frame timer, or cancel when not in play (awaiting a breaker or the Finish? prompt). `MatchPaused`, `MatchAutoPaused`, `MatchFinished`, `MatchAbandoned`, `MatchCancelled`, `MatchDeleted` cancel. Other matches are untouched.
- Ids derive from the match (`long-frame.<match>.<slot>`): a reschedule replaces the batch, and a cancel works after a relaunch.
- `LongFrameWarned` is not recorded: the warning can fire when no event can be stored.
- Wall-clock calendar triggers; a past date is delivered straight away. `ForegroundNotificationBanners` shows them in the foreground too.

## Composition-root wiring
    let notifications = UserNotificationsScheduler()
    let banners = ForegroundNotificationBanners()   // keep a strong reference
    UNUserNotificationCenter.current().delegate = banners
    let warnLongFrame = WarnLongFrame(matches: liveMatchesProjection, scheduler: notifications)
    warnLongFrame.subscribe(to: dispatcher)
    // at launch, after AutoPauseLiveMatches and loadLiveMatches:
    warnLongFrame.rescheduleAll()
    // when the first match starts (after Welcome); once granted, cover matches already running:
    Task { if await notifications.requestAuthorization() { warnLongFrame.rescheduleAll() } }

## Non-goals
- Configurable thresholds (out of scope, per decisions.md)

## Acceptance criteria
- Adapter tests: the schedule is computed correctly; it is rescheduled and cancelled on the right events (`LongFrameWarningTests`, `NotificationRequestTests`)
- Checked manually on the simulator

**Implementation skill:** `ddd-application-layer` (ports) · **Tests:** `ddd-testing`
