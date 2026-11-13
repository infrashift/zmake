---
id: "01a1d34e-cd36-7593-810f-e468e86de8a9"
title: "ISSUE-012: export and unexport"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-12"
  - "executor"
  - "open"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:08:39-06:00"
description: "Phase 12: export and unexport control the environment of each recipe line."
---

# ISSUE-012: export and unexport

**Status/Phase:** Open · Phase 12

## Description
GNU Make passes the variables from the environment and from the command line to each recipe. `export` adds file variables, and `unexport` removes variables.

## Acceptance Criteria
- [ ] `export NAME`, `export NAME = value` (all assignment operators), `export` alone, `unexport NAME` and `unexport` alone.
- [ ] `.EXPORT_ALL_VARIABLES`.
- [ ] The recipe environment gets the expanded value of each exported variable.
- [ ] A variable from the environment that the input file changes gets its new value.
- [ ] `make check` passes.

## Related
[PLAN.md](../../PLAN.md)
