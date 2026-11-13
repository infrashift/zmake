---
id: "01a1d34e-cd3c-7ee3-bb7b-857cd541af3c"
title: "ISSUE-013: vpath and VPATH"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-13"
  - "dag"
  - "open"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:08:39-06:00"
description: "Phase 13: directory search for prerequisites through VPATH and the vpath directive."
---

# ISSUE-013: vpath and VPATH

**Status/Phase:** Open · Phase 13

## Description
Find prerequisites in other directories, as GNU Make does. Automatic variables give the found path.

## Acceptance Criteria
- [ ] `VPATH = dir1:dir2` and `vpath PATTERN DIRS`, `vpath PATTERN`, `vpath`.
- [ ] Explicit and pattern prerequisites use the search. `$<` and `$^` give the found path.
- [ ] A target that is up to date in a vpath directory keeps the found path, as GNU Make does.
- [ ] `make check` passes.

## Related
[PLAN.md](../../PLAN.md)
