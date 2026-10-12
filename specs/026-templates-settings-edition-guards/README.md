---
status: complete
created: 2026-10-12
priority: high
tags:
- upgrade
- templates
- settings
depends_on:
- '23'
- '8'
- '7'
parent: '1'
created_at: 2026-10-12T15:13:40.464846Z
updated_at: 2026-10-12T15:32:59.703388Z
completed_at: 2026-10-12T15:32:59.703388Z
transitions:
- status: in-progress
  at: 2026-10-12T15:28:00.639783Z
- status: complete
  at: 2026-10-12T15:32:59.703388Z
---
# Templates & settings edition guards

## Overview
Enforce the Free limits on `Template` and `MatchSettings`, reading `CurrentEdition` (Upgrade, ADR-0011). Source: `docs/ddd-requirements.md` Changes section rows for `Template` and `MatchSettings`. Scenarios S1, S11, S12, S20, S21, S36, S44, S52.

## Requirements
- [x] `CreateOrUseTemplate`: runs whatever the edition (silently while Free)
- [x] `DeleteTemplate`: **Free: Scorer deletion refused; the S42 cascade is never limited**
- [x] `TemplateList`: **Free: replaced by an "Upgrade now" prompt in place**
- [x] `ChangeMatchDefaults`: **Free: style and break-rule changes refused; the game (S20) stays free**
- [x] `SetLiveMatchLimit`: **paid**
- [x] `LiveMatchLimit`: effective limit 1 while Free, whatever is stored

### UI (design language: 022)
- [x] New Game shows the "Upgrade now" prompt where the template list would be, opening the offer in place
- [x] Settings: style, break rule and limit refusals route to `ShowUpgradeOffer`; game stays editable

## Non-goals
- The `StartMatch` guard (Matches edition guards spec); the offer screens

## Acceptance criteria
**Free limits** (verbatim): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

- Integration (templates): templates recorded while Free appear on unlock; Free refuses deletion and shows the prompt
- Integration (settings): Free uses limit 1 and the Free defaults

**Implementation skills:** `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`

## Progress
- **Done (2026-10-12):**
  - `TemplateUseCases.deleteTemplate` refuses with `UpgradeRequired(.templates)` while Free. `deleteTemplates(of:)` (the S42 cascade), `combineTemplatesAfterMerge` and `createOrUseTemplate` don't read the edition, so templates are still recorded silently.
  - `TemplateListQuery` gains `showsUpgradePrompt`. While Free, `TemplateListProjection.templates` is empty and the prompt is shown. The stored rows are untouched, so they reappear on unlock. `TemplateUseCases.edition` passes its edition on to the list.
  - `MatchSettingsService` serves the effective values. While Free it uses the stored game, plus the stored style and break rule only if `FreeLimits` allows them; otherwise most frames wins and alternate. The live-match limit is `FreeLimits.liveMatches`. `effectiveDefaults` and `effectiveLiveMatchLimit` are public. `values` stays the stored values.
  - `ChangeMatchDefaults` while Free: a style change throws `UpgradeRequired(.raceTo / .sets)` and a break-rule change throws `.winnerBreaks`. A game change saves only the game, leaving the stored style and break rule alone.
  - `SetLiveMatchLimit` is the new throwing port method `setLiveMatchLimit(_:)` and throws `.severalLiveMatches` while Free. The old `changeLiveMatchLimit(_:)` now ignores a refusal.
  - The list and the settings re-render on `AppUnlocked` / `AppLocked`. `TemplateUseCases.subscribe` covers the list; `MatchSettingsService.subscribe(to:)` is wired in `AppContainer`.
  - UI: when Free, New Game shows a `TemplatesUpgradePrompt` row ("Upgrade now") where the Recent list would be. Tapping it calls `showUpgradeOffer(.templates)`. Swipe-delete and the Settings style, break and limit controls send `UpgradeRequired` to `showUpgradeOffer`. The game picker stays editable.
  - Integration tests (`TemplatesSettingsEditionTests`, real SQLite, `FixedEdition` flipped) cover:
    - templates recorded while Free appear on unlock
    - Free refuses deletion and shows the prompt
    - the cascade still runs while Free
    - Free uses the Free limit and defaults; stored values survive and come back on unlock
    - unchanged unlocked behaviour
- **Decisions:**
  - The effective values are computed on read. Nothing stored is rewritten, so unlocking needs no migration.
  - The prompt shows while Free even when no templates are stored, because it is the in-place offer (S52) and doesn't depend on there being data.
  - Matches maps its own style and break rule onto Upgrade's `MatchStyleKind` / `BreakRuleKind` with private helpers in `MatchSettingsService.swift`, to avoid clashing with the `StartMatch` guard work.
- **Remains:**
  - `StartMatch` still reads `settings.values.liveMatchLimit` (stored). The Matches guards spec should enforce `settings.effectiveLiveMatchLimit`, or `FreeLimits.liveMatches`, there.
  - The offer screen itself (Upgrade UI spec). `showUpgradeOffer` currently only sets `UpgradeOfferRouter.request`.
