---
status: planned
created: 2026-10-05
priority: medium
tags:
- matches
depends_on:
- '3'
- '6'
parent: '1'
created_at: 2026-10-05T10:42:31.475896Z
updated_at: 2026-10-05T10:42:31.475896Z
---

# Templates

## Overview
`Template`: every new setup becomes a template when its match starts and is listed most used first. Source: `docs/ddd-requirements.md` › Matches › Template. Scenarios S1, S2, S12, S33, S34, S36, S42.

## Requirements
- [ ] `Template.create(setup)`: use count 1. Raises `TemplateCreated`.
- [ ] `recordUse()`: +1. Raises `TemplateUsed`.
- [ ] `combine(with:)`: use counts add and the absorbed template is deleted. Raises `TemplatesCombined`.
- [ ] `delete()`: raises `TemplateDeleted`
- [ ] Invariant: at most one active template per `Setup`
- [ ] `TemplateRepository`: `getById`, `save`, `findBySetup`, `findByPlayer` (not event-sourced)
- [ ] `CreateOrUseTemplate`: policy on `MatchStarted`
- [ ] `DeleteTemplate`: on swipe
- [ ] `TemplateList` read model:
  - Fields: names, colours, game, style + targets as entered, break rule, use count
  - Most used first
  - An empty list routes New Match straight to the details screen

## UI (design language: 022)
- [ ] The **New Game** sheet opens on `TemplateList`, most used first:
  - Each row shows both players' colour plates and names, the game, the style and targets as entered, and the break rule
  - Swipe to delete (`DeleteTemplate`)
  - An "Enter details" row
- [ ] An empty list opens the sheet straight on the details step

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
