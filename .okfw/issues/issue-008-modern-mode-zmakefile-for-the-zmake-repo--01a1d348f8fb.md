---
id: "01a1d348-f8fb-774a-807b-ab4d404af1f5"
title: "ISSUE-008: Modern-mode ZMakefile for the zmake repo"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-7"
  - "modern-mode"
  - "closed"
created: "2026-11-12T23:02:17-06:00"
timestamp: "2026-11-12T23:02:17-06:00"
description: "Phase 7: a ZMakefile with the same targets as the Makefile, checked against GNU Make by the acceptance suite."
---

# ISSUE-008: Modern-mode ZMakefile for the zmake repo

**Status/Phase:** Closed · Phase 7

## Description
Add a modern-mode `ZMakefile` to the repo root with the same targets as the `Makefile`. [ADR-0010](/decisions/adr-0010-keep-a-modern-mode-zmakefile-next-to-the-makefile--01a1d348f8d1.md) records the design.

## Acceptance Criteria
- [x] `ZMakefile` declares every `Makefile` target as an `@name:` task, with space-indented recipes and no `.PHONY` list.
- [x] `tests/acceptance.sh` compares the dry run of each goal with GNU Make on the `Makefile`.
- [x] Scenario 7 still tests the `Makefile` in legacy mode.
- [x] `zmake check` (through the `ZMakefile`) and `make check` pass.

## Resolution
Done on 2026-11-12. `make check` and `zmake check` pass with 56 acceptance checks. strace shows that zmake opens `ZMakefile` without `-f`. A copy of the `ZMakefile` without one recipe line fails the comparison, so the gate detects drift. `zmake docs-demo` and `zmake docs-build` work through the `ZMakefile`.

## Related
[PLAN.md](../../PLAN.md) · [Syntax modes and target kinds](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md)
