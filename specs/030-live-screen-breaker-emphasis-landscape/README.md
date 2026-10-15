---
status: in-progress
created: 2026-10-12
priority: medium
tags:
- ui
- ios
- presentation
- matches
depends_on:
- '9'
- '22'
parent: '1'
created_at: 2026-10-12T17:46:59.284025Z
updated_at: 2026-10-12T17:48:46.287954Z
transitions:
- status: in-progress
  at: 2026-10-12T17:48:46.287954Z
---
# Live screen: breaker emphasis, steady scores, landscape

## Overview
Two problems on the live match screen:
- It's hard to see at a glance who is breaking, because the dot is small.
- A score shrinks once it reaches double digits, because `ScoreNumeral` uses `.minimumScaleFactor(0.5)` and each column scales on its own. The player with fewer frames then looks more prominent, which is backwards.

The business owner also wants to score with the phone turned sideways, with scores readable from the table. This is presentation only, so the domain model is unchanged: `LiveMatchScreen` already carries `isBreaker` per side. During `/ddd discovery` this was judged not to be a domain delta, so there is no ADR.

## Requirements
- [x] **Breaker emphasis.**
  - Once a breaker is chosen, their column is a little wider than the other player's, including a bigger score and name.
  - The emphasis moves when the break passes to the other player, animated unless Reduce Motion is on.
  - Before a breaker is chosen, the columns are equal. The breaker dot stays.
- [x] **Buttons are unaffected.** + and − are the same size on both sides, whoever is breaking.
- [x] **Steady score size.**
  - A score's size never depends on its number of digits: 9 and 10 render at the same point size.
  - The only size difference between the two scores is the breaker emphasis.
  - Size both scores from one shared metric that fits two digits; per-column `minimumScaleFactor` is not used.
- [x] **Landscape on the live screen only.**
  - The app supports landscape on the live match screen; every other screen stays portrait.
  - With the iPhone's rotation lock on, the screen stays portrait.
- [x] **Landscape layout.**
  - The players sit side by side, with each player's + and − on the outer edge next to their score.
  - Scores are much bigger than in portrait, and the breaker emphasis and steady size still apply.
  - Head-to-head, the timers, pause, the breaker dot and the sets score are all present, with the same Free-edition rules (no colours, head-to-head greyed, "Upgrade now" on pause).
- [ ] **Prompts in landscape.** Prompts shown on the live screen (Finish/Continue, end match, stale-match prompt, upgrade offer) appear over the landscape layout and work the same way.
- [ ] **Rotation loses nothing.** Turning the phone mid-frame keeps the frames, timers, break and any open prompt.

## Non-goals
- The lock screen and Live Activity (018) are unchanged.
- No new read-model fields or domain events.
- Landscape for any screen other than the live match screen.
- iPad (still an open decision in 022).

## Technical notes
- Live screen: `ios/Sources/Matches/Presentation/LiveMatchView.swift`. `PlayerColumn` holds the plate, name, dot, score and buttons.
- Score: `ios/Sources/Shared/DesignSystem/ScoreNumeral.swift`. Its hero size is a 190 pt `@ScaledMetric` with `.minimumScaleFactor(0.5)`, which causes the shrink. Remove the minimum scale factor from the live screen only, and keep it for rows.
- Orientation: `ios/project.yml:35` and `ios/App/Info.plist` are portrait-only. The app has to allow landscape and then lock every other screen to portrait, for example with an app-delegate `supportedInterfaceOrientations` driven by the presented screen, or `requestGeometryUpdate`.
- Accessibility: Dynamic Type up to accessibility sizes, 44 pt minimum touch targets, and VoiceOver still reading "Asher 4, Me 3" (022).

## Acceptance criteria
- In the simulator, the breaker's column is visibly bigger and the emphasis moves on + and −. The columns are equal before a breaker is chosen.
- The + and − buttons have the same frame in both columns.
- The 9 → 10 score transition keeps the same point size; check it with 10–9 and 9–10 in both orientations.
- Rotating on the live screen shows the side-by-side layout, and every other screen stays portrait. With rotation lock on, the screen stays portrait.
- The layout is checked in Light, Dark and large Dynamic Type, in both Free and Unlocked, and for a sets match.

## Progress (2026-10-12)
- **Built:**
  - `ScoreboardSizing` (DesignSystem) holds the pure sizing rules, tested in `Tests/Shared/DesignSystemTests`. The breaker gets a 56 / 44 split, both font size and width scale together, scores are always sized for two digits, and the base size fits the measured height.
  - `ScoreSize.points` is an exact size that never shrinks; rows and lists keep `.hero` / `.row` as they were.
  - `Scoreboard` in `LiveMatchView.swift` lays out rows of names, scores and buttons that share the column widths. The scores fill the measured height between the names and the buttons. In landscape, each player's buttons sit on the outer edge.
  - `OrientationLock` and `AppDelegate`: the plist allows landscape, the delegate answers from the lock, and the live screen opens it on appear and closes it on disappear, returning to portrait.
- **Landscape:**
  - The clocks, game, style and "Paused" move into the navigation bar.
  - The paused bar is dropped because Resume stays in the toolbar.
  - Head-to-head shrinks to one line.
- **Decision:** the breaker's name is a size up (title2 vs title3), as well as the score.
- **Learning:** sizing the scores from an estimated height let the bigger column overflow while paused, and SwiftUI then shrank the breaker's name. The fix is to measure the score region itself.
- **Verified in the simulator at 10–9, Free, Light:**
  - Portrait, live and paused.
  - Landscape, paused.
  - The breaker is bigger and the buttons are equal.
  - 9 and 10 stay at the same size.
- **Not yet verified:**
  - Rotation lock on; leaving the live screen while sideways.
  - Prompts over landscape.
  - Dark Mode and large Dynamic Type.
  - Unlocked with head-to-head figures.
  - A sets match.
  - Before a breaker is chosen.
