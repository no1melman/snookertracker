# Tasks

Specs in `specs/` are the source of truth for scope; this list tracks session-level work.

## Done
- [x] Scaffold SwiftPM modules per context + layer, xcodegen app target (002)
- [x] App shell: hub, design system (PlayerPlate, ScoreNumeral), Settings, Players, Welcome, New Game, live screen (022)
- [x] Matches domain: value objects, live play, ending/corrections (003, 004, 005)
- [x] Players domain + MeSetting (011, 012 domain)
- [x] SQLite event store + persistence for matches, players, Me, settings (006, 007)
- [x] Templates on New Game (008)
- [x] Stats match records + History + match detail, with backfill (013)
- [x] Auto-pause after kill (020 S27) + ADR-0007: no auto-pause on background launch
- [x] Live Activity + Dynamic Island with +/pause buttons (018)
- [x] App icon (red 1 + yellow 9 pool balls; `ios/Design/icon/icon.swift`)
- [x] Running on the user's iPhone (team 8V5TQR6N9X in ios/project.yml)
- [x] ADR-0006 event sourcing (Q6 resolved, spec 004 complete)
- [x] Spec audit with Progress sections; statuses set

## Next
- [ ] Commit the ADR-0006/0007 + option-A change (uncommitted at sign-off)
- [ ] Verify on device: lock-screen Live Activity, Dynamic Island, + after iOS reclaims the app (ADR-0007)
- [ ] 015 Match ending use cases: delete / correct score / mark finished from History, Finish all, stale prompt (S28 → `afterAutoPause` in AppContainer)
- [ ] 014 Head-to-head strip on live screen + Stats screen
- [ ] 011 remainder: archive / unarchive / merge / remove + OHS `IsPlayerInLiveMatch`, `HavePlayedEachOther`
- [ ] 010 remainder: correct breaker, colour-clash override, "already live" check, Settings link on limit alert
- [ ] 009 remainder: sets score format/UI, combined VoiceOver score
- [ ] Match detail: show breaker per frame
- [ ] 016/017 Series, 019 notifications (long-frame warnings), 021 export, 012 walkthrough
- [ ] Decide Q1–Q4 (code currently: Q1 atomic, Q2 replaces, Q3 + disabled on prompt, Q4 arrival order) and record via /ddd delta
- [ ] TestFlight: enrol in Apple Developer Program, App Store Connect record, archive/upload script
- [ ] 022 finish: Impeccable review, DESIGN.md, Dynamic Type/VoiceOver checks
