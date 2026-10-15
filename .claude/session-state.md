# Session state — 2026-10-05

Took the project from specs-only to a working iOS app on the user's iPhone: SwiftPM modules per context, SwiftUI shell, real Matches/Players domains, SQLite event-sourced persistence, templates, History, auto-pause, Live Activity and an app icon. Work was fanned out to parallel subagents with disjoint file ownership and private build scratch paths.

**Left mid-task:** the ADR-0006/0007 docs and the option-A lifecycle change (`AppLaunchState.swift`, `AppLifecycle.beginSession(launchedInBackground:)`) are built and tested but not committed.

**Pick up next:** commit, then verify the Live Activity on the phone (lock screen, Dynamic Island, + after iOS reclaims the app), then spec 015 (delete/correct/mark finished from History, Finish all, stale prompt).

**Decisions worth remembering**
- Persistence: SQLite via system `SQLite3` (`SQLiteSupport` module), one DB file in Application Support; match is event-sourced (ADR-0006), other aggregates state-stored.
- ADR-0007: background launches (lock-screen buttons) never auto-pause.
- Free personal team signing; avoid App Groups/push. Live Activity buttons run in the app process.
- `ios/project.yml` is the source of the Xcode project (`cd ios && xcodegen generate`); `.xcodeproj` is gitignored.
- lean-spec CLI runs via `nix-shell -p nodejs --run 'npx -y lean-spec ...'`.
- Q1–Q4 still deferred in `docs/domain/decisions.md`; code behaviour noted in tasks.md.
