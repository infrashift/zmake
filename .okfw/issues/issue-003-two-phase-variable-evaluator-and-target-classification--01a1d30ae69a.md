---
id: "01a1d30a-e69a-7665-b991-0ef5c11606b9"
title: "ISSUE-003: Two-phase variable evaluator and target classification"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "open"
  - "phase-3"
  - "eval"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "Phase 3: variable flavors, immediate and deferred expansion, automatic variables, functions and the target kind classifier."
---

# ISSUE-003: Two-phase variable evaluator and target classification

# ISSUE-003: Two-phase variable evaluator and target classification

**Status/Phase:** Open · Phase 3

## Description
Build `src/eval.zig` without recursion ([ADR-0003](/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md)).

## Acceptance Criteria
- [ ] The variable table applies the precedence command line > input file > environment.
- [ ] `:=` expands at once. `=` expands when zmake uses the value. `?=` and `+=` follow GNU semantics.
- [ ] Expansion supports `$(X)`, `${X}`, `$X`, `$$` and substitution references.
- [ ] Automatic variables `$@`, `$<`, `$^`, `$*`, `$?`, `$(@D)` and `$(@F)` expand.
- [ ] The functions `wildcard`, `shell`, `patsubst` and `subst` work. `$(MAKE)` gives the zmake path.
- [ ] The classifier follows the [Syntax modes](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md) spec.
- [ ] `make lint test` passes.

## Related
[Architecture](/architecture/zmake-architecture-overview--01a1d30ae65a.md) · [PLAN.md](../../PLAN.md)
