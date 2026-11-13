---
id: "01a1d34e-cd36-7593-810f-e468e86de8a9"
title: "ISSUE-012: export and unexport"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-12"
  - "executor"
  - "closed"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:48:04-06:00"
description: "Phase 12: export and unexport control the environment of each recipe line."
---

# ISSUE-012: export and unexport

**Status/Phase:** Closed · Phase 12

## Description
GNU Make passes the variables from the environment and from the command line to each recipe. `export` adds file variables, and `unexport` removes variables.

## Acceptance Criteria
- [x] `export NAME`, `export NAME = value` (all assignment operators), `export` alone, `unexport NAME` and `unexport` alone.
- [x] `.EXPORT_ALL_VARIABLES`.
- [x] The recipe environment gets the expanded value of each exported variable.
- [x] A variable from the environment that the input file changes gets its new value.
- [x] `make check` passes.

## Resolution
Done on 2026-11-12 in Phase 12. `make check` passes.

- `export`, `unexport`, `export` alone, `unexport` alone and `.EXPORT_ALL_VARIABLES` work, also `export define`, `export override` and `override export` ([ADR-0014](/decisions/adr-0014-export-flags-decide-the-recipe-environment--01a1d37290f3.md)).
- `Evaluator.exported` decides for each variable. The executor builds the environment of each job and expands exported values with the automatic variables of the target.
- Jobs share the base environment when no variable needs an export, so a plain Makefile has no extra cost.
- Acceptance scenario 13 compares the recipe environment with GNU Make 4.3 in four cases. All match.

## Related
[PLAN.md](../../PLAN.md)
