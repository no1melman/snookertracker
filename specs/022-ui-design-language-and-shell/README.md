---
status: in-progress
created: 2026-10-05
priority: high
tags:
- ui
- ios
- presentation
depends_on:
- '9'
- '10'
- '14'
parent: '1'
created_at: 2026-10-05T19:02:44.901563Z
updated_at: 2026-10-05T19:18:16.788994Z
transitions:
- status: in-progress
  at: 2026-10-05T19:18:16.788994Z
---

# UI design language & app shell

## Overview
This spec sets the design language and navigation shell for the SwiftUI presentation layer. It is the "initial UI harness" that spec 001 plans. Product truth is in `PRODUCT.md`. This spec decides how the screens look and fit together. The read models (009, 013/014) and use cases (010, 015) own the data and behaviour.

**Direction:** stock SwiftUI and the HIG, executed at full craft, with no invented visual world. The quality bar is **Flighty** and **Apple Sports**: native, data-dense live status, large confident numerals, head-to-head summaries, and first-class Live Activities. **Ruled out:** a TV-broadcast scoreboard look, a sterile settings-list look, novelty baize and chalk, and gamification.

**Scene:** a snooker or pool club. The phone lies face-up on the rail, read from 1–3 m and tapped in passing, or comes out of a pocket, often to the lock screen. Mode: Operate.

## Design language
- System colours and materials, SF Pro and SF Symbols, and one tint. Dark Mode and Light Mode both follow the system setting.
- **Player colours** work like team colours in Apple Sports: one fixed colour per player, consistent on every screen. They are the main saturated colour; the tint is for controls only.
- **Numerals:** scores are large and use monospaced digits, so they don't shift as they change. Frame counts must read from the rail.
- Hub rows carry real content: live scores and match timers. Inset grouped lists are kept for Settings and player editing.
- Haptic on + and −.

## Requirements
This spec owns the design language, the hub shell and the Settings container. Each screen's requirements live in the spec that owns its read model or use case, in that spec's "UI (design language: 022)" section.

- [ ] **Hub** (the root of one `NavigationStack`, with a large title and no tab bar):
  - **New Game** is the prominent first row
  - The **Live** section shows only when matches are live (009), with Finish all (015)
  - Then rows for History, Stats, Series, Players and Settings, and "Me (name)" (012)
- [ ] **Settings** (an inset grouped list) contains the match defaults and live-match limit (007), Me and Replay walkthrough (012)
- [ ] A shared **player plate** component (colour plate plus name) used on every screen; archived players are greyed
- [x] A shared **score numeral** style: monospaced digits that scale with Dynamic Type

### Screen map
| Screen | Owning specs |
| --- | --- |
| New Game: templates, details, breaker | 008, 010, 011, 007 |
| Live screen: layout, paused state | 009 |
| Live screen: controls and prompts | 010, 015 |
| Head-to-head strip | 014 (via 009) |
| History and match detail | 013, 015 |
| Stats | 014 |
| Series and monthly summary | 016, 017 |
| Players | 011 |
| Welcome and Me | 012 |
| Stale prompt | 020, 015 |
| Live Activity and Dynamic Island | 018 |

## Ranges & states
- Names up to about 20 characters; frame counts from 0 to about 30; set scores; several live matches at once.
- Empty states: no live matches, no history, no head-to-head yet, no series.

## Constraints
- iOS 17+, SwiftUI. Presentation code depends only on application-layer queries and commands (spec 002).
- Dynamic Type everywhere, including scores up to accessibility sizes. 44 pt minimum touch targets, with + sized for a passing thumb.
- VoiceOver reads a live score as "Asher 4, Me 3" (the frame number is derived from the score). Reduce Motion is respected.
- Edge-swipe back, system sheets and alerts. No custom navigation chrome.

## Open decisions
- The tint colour, and the fixed set of player colours to choose from
- Whether the hub shows recent results or series standings under its rows
- iPad support
- The final app name
- What + does while a Finish prompt is showing (Q3, decided in spec 010)
- **Read-model gaps that need `/ddd delta`.** The doc wins, so these are not in the child specs yet:
  - The live screen's target ("Race to 5") needs the style and targets in `LiveMatchScreen`
  - An Altered label in History needs a corrected flag in `PastMatches`
  - The breaker per frame in match detail needs a breaker field in `MatchTimeline`

## Acceptance criteria
- Every screen above is built with stock SwiftUI components and checked in the simulator in Light Mode, Dark Mode and at a large Dynamic Type size
- A live score reads from arm's length on a phone lying on a table
- Screen requirements are spread into the owning specs (done 2026-10-05; see the screen map)
- Impeccable finish review passes; DESIGN.md records the tokens actually used

## Progress
- **Done (2026-10-05 audit):**
  - `HubView` (`ios/Sources/AppComposition/Shell/`) is one `NavigationStack` with a large title and no tab bar. It has New Game first, the Live section (009), then History, Stats, Series, Players and Settings, and a Me row.
  - `SettingsView` is a `Form` holding the match defaults, the limit stepper and Me.
  - `DesignSystem` provides `ScoreNumeral` (monospaced, `@ScaledMetric` hero size), `PlayerPlate` (archived rows greyed), `PlayerColour` and haptics on +/−.
- **Decisions:** the tint and the 12-colour palette are placeholders (`Theme.swift`) until the open decision is made. History, Stats and Series rows open a "Coming soon" placeholder.
- **Remains:**
  - Finish all in the Live section (015).
  - Replay walkthrough in Settings (012).
  - The live screen draws its own capsule plate instead of using `PlayerPlate`.
  - The real History, Stats and Series screens.
  - The simulator checks in Light, Dark and large Dynamic Type.
  - The Impeccable finish review and `DESIGN.md`, which doesn't exist yet.

## Notes
- Shaped with `/impeccable shape` on 2026-10-05. The decision round was offered several invented visual worlds; the user chose the native category standard.
