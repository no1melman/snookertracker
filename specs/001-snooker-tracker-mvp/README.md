---
status: planned
created: 2026-10-05
priority: high
tags:
- umbrella
- ddd
created_at: 2026-10-05T10:40:34.473694Z
updated_at: 2026-10-05T10:40:34.473694Z
---

# Snooker Tracker MVP (umbrella)

## Overview

Build the Snooker Tracker iOS app (Swift) for scoring pool and snooker matches, managing players and reporting stats. **Source of truth:** `docs/ddd-requirements.md`, requirements revision ADR-0001 (model ADR-0001, strategy ADR-0002/ADR-0003). It covers three bounded contexts: **Matches** (core), **Players** (supporting) and **Stats** (core). The project is greenfield, so every item is a **build**.

The constraints and invariants in `docs/ddd-requirements.md` are binding. The child specs group its items into slices you can implement; they never restate a rule differently. If a child spec and the requirements doc disagree, the doc wins.

## Requirements

- [ ] Every item in `docs/ddd-requirements.md` is covered by exactly one child spec
- [ ] All child specs complete
- [ ] `/ddd conformance` passes against the requirements doc with no `missing` or `diverges` verdicts

## Non-goals

- The out-of-scope scenarios in `docs/domain/decisions.md`: S23 loss reasons, S24 web upload, shared or watched matches, shot clocks, leagues and the rest. Only the **design-for-later constraints** are in scope (see the project-structure child spec).
- Answering the deferred open questions Q1–Q5. They are revisited inside the specs that own them.

## Acceptance criteria

- Every child spec is `complete`, verified against tests and code
- A conformance report shows every requirement item `conformant`
- Scenario docs in `docs/domain/scenarios/` are flipped to `Status: existing`

## Notes

- **UI:** the design language and app shell are in `022-ui-design-language-and-shell` (native SwiftUI, with Flighty and Apple Sports as the quality bar). Next, spread its screen requirements into the child specs that own each read model and use case.

- Each requirement item names its implementation skill (`ddd-tactical-patterns`, `ddd-event-sourcing`, `ddd-cqrs` and so on). Invoke that skill when you implement the item.
- When the domain model changes, re-run `/ddd delta`, then `ddd-requirements`. Its "Changes since last revision" table drives the spec updates.
