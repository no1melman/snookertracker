---
status: in-progress
created: 2026-10-05
priority: medium
tags:
- matches
depends_on:
- '3'
- '6'
parent: '1'
created_at: 2026-10-05T10:42:31.475896Z
updated_at: 2026-10-05T20:46:00.423840Z
transitions:
- status: in-progress
  at: 2026-10-05T20:46:00.423840Z
---

# Templates

## Overview
`Template`: every new setup becomes a template when its match starts and is listed most used first. Source: `docs/ddd-requirements.md` › Matches › Template. Scenarios S1, S2, S12, S33, S34, S36, S42.

## Requirements
- [x] `Template.create(setup)`: use count 1. Raises `TemplateCreated`.
- [x] `recordUse()`: +1. Raises `TemplateUsed`.
- [x] `combine(with:)`: use counts add and the absorbed template is deleted. Raises `TemplatesCombined`.
- [x] `delete()`: raises `TemplateDeleted`
- [x] Invariant: at most one active template per `Setup`
- [x] `TemplateRepository`: `getById`, `save`, `findBySetup`, `findByPlayer` (not event-sourced)
- [x] `CreateOrUseTemplate`: policy on `MatchStarted`
- [x] `DeleteTemplate`: on swipe
- [x] `TemplateList` read model:
  - Fields: names, colours, game, style + targets as entered, break rule, use count
  - Most used first
  - An empty list routes New Match straight to the details screen

## UI (design language: 022)
- [x] The **New Game** sheet opens on `TemplateList`, most used first:
  - Each row shows both players' colour plates and names, the game, the style and targets as entered, and the break rule
  - Swipe to delete (`DeleteTemplate`)
  - An "Enter details" row
- [x] An empty list opens the sheet straight on the details step

## Non-goals
- Editing a template (not in the model)
- Reacting to player events (archived hiding, removal and merge policies): in the players spec (011), which depends on this one

## Acceptance criteria
- Domain unit tests: create, recordUse, combine (counts add), delete, one per setup
- Integration tests:
  - Create-or-use on start
  - A deleted template is recreated with count 1
  - List ordering
  - Empty-list routing

**Implementation skills:** `ddd-tactical-patterns`, `ddd-repositories`, `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`

## Progress
- **Done (verified against code 2026-10-06):**
  - Domain: `Sources/Matches/Domain/Templates/Template.swift` (`create`, `recordUse`, `combine`, `delete`; `TemplateUse.record` applies one-per-setup). Tests in `Tests/Matches/DomainTests/TemplateTests.swift`.
  - `SQLiteTemplateRepository`: the UNIQUE `setup_key` backs the invariant. It also serves `TemplateListReader`, ordered by use count, then most recently used.
  - `TemplateUseCases`: `CreateOrUseTemplate` subscribes to the published `MatchStarted`, and `DeleteTemplate` handles the swipe. `TemplateListProjection` resolves names and colours at read time.
  - `NewGameView`: a "Recent" section of templates sits above the details form, with icon-only swipe-to-delete. With no templates, only the details form shows.
  - Integration tests are in `Tests/Matches/IntegrationTests/TemplateIntegrationTests.swift`.
- **Decisions:**
  - "Enter details" is the details form's section header ("Or enter details") under the template list, not a row that navigates to a separate step.
  - Spec 011 added `movePlayer(from:to:)`, which raises `TemplatePlayerMoved`, so a merge can repoint a template before combining it.
