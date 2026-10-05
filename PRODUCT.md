# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Swift. Each bounded context (Matches, Players, Stats) is a SwiftPM module with domain, application, infrastructure and presentation layers. An iOS app target is the composition root (spec 002). The presentation layer is **SwiftUI**, which also covers the Live Activity and WidgetKit surfaces.

## Users

A small, known group of friends who play pool and snooker together. The **Scorer** is whoever is holding the phone, and is usually also one of the players. They record a match live on that one phone, at the table, between shots. "Me" is the device owner's player.

This is for private use: one person's phone and their circle of opponents. It is not a product for strangers.

## Product Purpose

The app keeps an accurate live score of pool and snooker matches, then turns those matches into a long-running record of who beats whom. A match succeeds when scoring took no attention away from playing and the result is in the history afterwards.

## Positioning

What it does that a generic scorekeeper or notes on a phone can't:

- **Rivalries that build up over time.** It shows head-to-head records, series with monthly summaries, deciders, and stats by opponent and by day of the week ("Asher on Fridays").
- **The fastest possible live scoring.** Each player has a single +/− control, and the break moves automatically. A lock-screen Live Activity offers + and pause/resume.
- **Honest records.** Corrections never overwrite: the original score is kept as an alteration. Every bit of saved state can be exported in full.
- **Made for one group.** It is a personal tool for a known set of opponents, so it has no accounts, onboarding funnels or social features.

## Operating Context

- Matches happen in a **snooker or pool club**: bright light over the table, a darker room around it, and matches that can run long. Between shots the scorer picks up the phone, glances at it and taps it, or uses the lock screen.
- Pool is the default game. Match styles are most frames wins, race to N, or sets, entered as "race to" or "best of" with odd numbers only.
- Several matches can be live at once, up to a limit set in Settings. The Live Activity shows the oldest live match.
- Long-frame warnings fire at 30 minutes and then every 10 minutes. The app auto-pauses a match if it is killed (ADR-0005) and checks for stale matches on launch.
- History, stats and corrections are reviewed after the match, away from the table.

## Capabilities and Constraints

- **Live play:** start a match from a template or by entering the details, choose who breaks, score with +/−, pause and resume, and finish, abandon or cancel the match.
- **Templates:** created automatically from setups that have been played, and can be deleted.
- **Corrections:** correct an ended match's score (kept as an alteration), correct the breaker, delete a match, or mark an abandoned match finished.
- **Players:** add, rename, merge, archive, unarchive, remove, set colour, and give a player a temporary colour for one match.
- **Stats:** head-to-head shown on the live screen, results by opponent and by day of the week, deciders, and series.
- **Settings:** default game, match style, break rule, the live-match limit, and who "Me" is.
- **First launch:** asks for your name, then shows a walkthrough you can skip and replay from Settings (S48).
- **Storage:** a local on-device database, so the app works offline by default. It has no accounts or sync, and the full state must be exportable (spec 021).
- **Terminology** follows `docs/domain/glossary.md`: Scorer, Me, frame, match, series, decider, template, alteration.
- **Deferred:** scoring one match from two phones, spectating from another device, leagues, WhatsApp sharing, shot clocks, and an Android app.
- **Undecided:** the final product name ("Snooker Tracker" is a working name) and the persistence engine.

## Brand Commitments

- "Snooker Tracker" is a working name and may change.
- **Native iOS by choice (2026-10-05).** The app is built from stock SwiftUI and HIG components: system colours, SF Pro and SF Symbols, system materials and one tint. It is executed at full craft, with no invented visual world. The bar is set by **Flighty** and **Apple Sports**: native, data-dense live status, large confident numerals, head-to-head summaries, and Live Activities that are first-class.
- **Ruled out:** a TV-broadcast scoreboard look, a sterile settings-list look, novelty baize and chalk, and gamification (badges, streaks, confetti).

## Evidence on Hand

No UI, screenshots, logos or other assets exist yet. The domain model lives in `docs/domain/` (45 scenarios), in `docs/ddd-requirements.md`, and in ADRs 0001–0005. The opponent names in the docs, such as Asher, are real friends, used as examples. Do not invent users, reviews or App Store claims.

## Product Principles

1. **The table comes first.** Scoring has to be possible with a glance and a tap in club lighting, without breaking concentration on the game.
2. **Records are sacred.** Never lose or silently rewrite a result. Corrections are visible, and the data belongs to the user.
3. **History is the payoff.** Every match adds to a rivalry, so the record after a match matters as much as the live score.
4. **Built for friends, not a market.** Leave out growth mechanics, accounts and social features. Familiarity is assumed.
