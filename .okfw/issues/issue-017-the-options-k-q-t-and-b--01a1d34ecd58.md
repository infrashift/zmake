---
id: "01a1d34e-cd58-7b4b-a0cf-be318067e367"
title: "ISSUE-017: The options -k, -q, -t and -B"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-17"
  - "cli"
  - "closed"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-13T00:20:06-06:00"
description: "Phase 17: keep going, question, touch and always-make, and combined short options."
---

# ISSUE-017: The options -k, -q, -t and -B

**Status/Phase:** Closed · Phase 17

## Description
Add the common GNU Make options. Pass them to sub-makes through MAKEFLAGS.

## Acceptance Criteria
- [x] `-k` continues with other targets after a failure. The exit code stays 2.
- [x] `-q` runs nothing. The exit code is 0 when the goals are up to date, else 1.
- [x] `-t` touches the out-of-date file targets and runs no recipe.
- [x] `-B` treats every target as out of date.
- [x] Combined short options such as `-kj4` and `-nB`.
- [x] `make check` passes.

## Resolution
Done on 2026-11-13 in Phase 17. `make check` passes: 97 unit tests, 94 acceptance checks.

- `-k`, `-q`, `-t`, `-B` and `-s` work, with their long forms and in clusters such as `-kj4` ([ADR-0019](/decisions/adr-0019-letter-flags-share-one-table-for-options-and-makeflags--01a1d390363b.md)).
- The flags pass to sub-makes as letters in `MAKEFLAGS`, in the order of GNU Make.
- `-q` exits with 1 when a goal is out of date.
- Acceptance scenario 18 matches GNU Make 4.3 in twelve cases, also the exit codes.
- Difference: under `-q` and `-t`, zmake does not run lines with `+` or `$(MAKE)`.

## Related
[PLAN.md](../../PLAN.md)
