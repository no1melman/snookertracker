---
status: planned
created: 2026-10-05
priority: low
tags:
- cross-cutting
- infrastructure
depends_on:
- '6'
- '7'
- '8'
- '11'
- '12'
- '16'
parent: '1'
created_at: 2026-10-05T16:46:18.611307Z
updated_at: 2026-10-05T16:46:21.450806Z
---

# Full-state export (design for later)

## Overview
S24 (uploading everything to the web) is out of scope, but its design constraint is not: all saved state must be exportable in full. This spec owns that constraint across every store. Source: `docs/ddd-requirements.md` › Cross-cutting › Design-for-later constraints; `docs/domain/decisions.md` (S24).

## Requirements
- [ ] An `ExportAllState` port in application, with one adapter per store
- [ ] The export contains:
  - Every match's full event stream, in order (006)
  - All players, including archived (011)
  - Templates (008), series (016), match settings (007) and the Me setting (012)
- [ ] The format is versioned and uses the same versioned event contract as the published Stage 2 events
- [ ] No upload, no UI: the export is produced in-process for tests and future use

## Non-goals
- Uploading, importing or syncing (S24 itself)
- Backups to files (out of scope, per decisions.md)

## Acceptance criteria
- Integration test: seed every store, export, and check that each item and every match event is present, in order
- Adding a new store without an export adapter fails a test (a registry of exportable stores)

**Implementation skills:** `ddd-application-layer`, `ddd-repositories` · **Tests:** `ddd-testing`
