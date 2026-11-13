---
id: "01a1d34e-cd5f-7d5d-8942-912b44b1d2ad"
title: "ISSUE-018: Quoted values in MAKEFLAGS"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-18"
  - "jobserver"
  - "open"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:08:39-06:00"
description: "Phase 18: command-line variables with spaces survive the trip through MAKEFLAGS."
---

# ISSUE-018: Quoted values in MAKEFLAGS

**Status/Phase:** Open · Phase 18

## Description
GNU Make escapes white space and backslashes in the overrides of `MAKEFLAGS`. zmake splits on spaces and loses the value.

## Acceptance Criteria
- [ ] `composeMakeflags` escapes spaces, tabs and backslashes as GNU Make does.
- [ ] `parseMakeflags` reads the escaped form from GNU Make and from zmake.
- [ ] A sub-make gets `X='a b'` intact, also through GNU Make.
- [ ] `make check` passes.

## Related
[PLAN.md](../../PLAN.md)
