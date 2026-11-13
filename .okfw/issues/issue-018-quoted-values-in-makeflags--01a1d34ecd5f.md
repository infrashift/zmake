---
id: "01a1d34e-cd5f-7d5d-8942-912b44b1d2ad"
title: "ISSUE-018: Quoted values in MAKEFLAGS"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-18"
  - "jobserver"
  - "closed"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-13T00:23:16-06:00"
description: "Phase 18: command-line variables with spaces survive the trip through MAKEFLAGS."
---

# ISSUE-018: Quoted values in MAKEFLAGS

**Status/Phase:** Closed · Phase 18

## Description
GNU Make escapes white space and backslashes in the overrides of `MAKEFLAGS`. zmake splits on spaces and loses the value.

## Acceptance Criteria
- [x] `composeMakeflags` escapes spaces, tabs and backslashes as GNU Make does.
- [x] `parseMakeflags` reads the escaped form from GNU Make and from zmake.
- [x] A sub-make gets `X='a b'` intact, also through GNU Make.
- [x] `make check` passes.

## Resolution
Done on 2026-11-13 in Phase 18. `make check` passes: 97 unit tests, 96 acceptance checks.

- `composeMakeflags` writes a backslash before each space, tab and backslash of an override, and writes the overrides in reverse order, as GNU Make does.
- `parseMakeflags` splits at white space that no backslash escapes and takes the character after each backslash literally. `NAME:=value` stays a simple variable.
- Acceptance scenario 19 compares the bytes of `MAKEFLAGS` and the values in a sub-make with GNU Make 4.3. All match.
- The first probe used `echo`, which changes backslashes in dash. The probe now uses `printf '%s'`.

## Related
[PLAN.md](../../PLAN.md)
