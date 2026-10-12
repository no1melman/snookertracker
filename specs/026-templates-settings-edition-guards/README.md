---
status: planned
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
updated_at: 2026-10-12T15:13:40.464846Z
---

# Templates & settings edition guards

## Overview
Enforce the Free limits on `Template` and `MatchSettings`, reading `CurrentEdition` (Upgrade, ADR-0011). Source: `docs/ddd-requirements.md` Changes section rows for `Template` and `MatchSettings`. Scenarios S1, S11, S12, S20, S21, S36, S44, S52.

## Requirements
- [ ] `CreateOrUseTemplate`: runs whatever the edition (silently while Free)
- [ ] `DeleteTemplate`: **Free: Scorer deletion refused; the S42 cascade is never limited**
- [ ] `TemplateList`: **Free: replaced by an "Upgrade now" prompt in place**
- [ ] `ChangeMatchDefaults`: **Free: style and break-rule changes refused; the game (S20) stays free**
- [ ] `SetLiveMatchLimit`: **paid**
- [ ] `LiveMatchLimit`: effective limit 1 while Free, whatever is stored

### UI (design language: 022)
- [ ] New Game shows the "Upgrade now" prompt where the template list would be, opening the offer in place
- [ ] Settings: style, break rule and limit refusals route to `ShowUpgradeOffer`; game stays editable

## Non-goals
- The `StartMatch` guard (Matches edition guards spec); the offer screens

## Acceptance criteria
**Free limits** (verbatim): 1 live match · most frames wins only · alternate breaks only · 5 active players (Me included, archived not counted) · newest 10 ended matches shown · no colours, templates, pause by hand, head-to-head, stats, series or lock screen. Auto-pause after a kill and resuming from it stay free. A refused action opens the upgrade offer (S52). Nothing is ever deleted or rewritten to enforce a limit.

- Integration (templates): templates recorded while Free appear on unlock; Free refuses deletion and shows the prompt
- Integration (settings): Free uses limit 1 and the Free defaults

**Implementation skills:** `ddd-application-layer`, `ddd-cqrs` · **Tests:** `ddd-testing`
