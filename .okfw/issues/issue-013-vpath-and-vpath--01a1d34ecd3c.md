---
id: "01a1d34e-cd3c-7ee3-bb7b-857cd541af3c"
title: "ISSUE-013: vpath and VPATH"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-13"
  - "dag"
  - "closed"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:51:42-06:00"
description: "Phase 13: directory search for prerequisites through VPATH and the vpath directive."
---

# ISSUE-013: vpath and VPATH

**Status/Phase:** Closed · Phase 13

## Description
Find prerequisites in other directories, as GNU Make does. Automatic variables give the found path.

## Acceptance Criteria
- [x] `VPATH = dir1:dir2` and `vpath PATTERN DIRS`, `vpath PATTERN`, `vpath`.
- [x] Explicit and pattern prerequisites use the search. `$<` and `$^` give the found path.
- [x] A target that is up to date in a vpath directory keeps the found path, as GNU Make does.
- [x] `make check` passes.

## Resolution
Done on 2026-11-12 in Phase 13. `make check` passes.

- `VPATH` and `vpath` (with `vpath PATTERN` and `vpath` alone to clear) work ([ADR-0015](/decisions/adr-0015-directory-search-keeps-the-found-path-per-node--01a1d376370d.md)).
- `dag.locate` searches the matching `vpath` entries, then `VPATH`. Nodes keep the found path. Pattern rule viability uses the same search.
- The automatic variables give the found paths. An out-of-date target found by the search rebuilds in the working directory under its own name.
- Acceptance scenario 14 runs eight cases through GNU Make 4.3 and zmake. The output is the same.

## Related
[PLAN.md](../../PLAN.md)
