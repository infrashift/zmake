---
id: "01a1d30a-e69a-7665-b991-0ef5c11606b9"
title: "ISSUE-003: Two-phase variable evaluator and target classification"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-3"
  - "eval"
  - "closed"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T22:12:03-06:00"
description: "Phase 3: variable flavors, immediate and deferred expansion, automatic variables, functions and the target kind classifier."
---

# ISSUE-003: Two-phase variable evaluator and target classification

**Status/Phase:** Closed · Phase 3

## Description
Build `src/eval.zig` without recursion ([ADR-0003](/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md)).

## Acceptance Criteria
- [x] The variable table applies the precedence command line > input file > environment.
- [x] `:=` expands at once. `=` expands when zmake uses the value. `?=` and `+=` follow GNU semantics.
- [x] Expansion supports `$(X)`, `${X}`, `$X`, `$$` and substitution references.
- [x] Automatic variables `$@`, `$<`, `$^`, `$*`, `$?`, `$(@D)` and `$(@F)` expand.
- [x] The functions `wildcard`, `shell`, `patsubst` and `subst` work. `$(MAKE)` gives the zmake path.
- [x] The classifier follows the [Syntax modes](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md) spec.
- [x] `make lint test` passes.

## Resolution
Done on 2026-11-12. `make lint test` passes: 62 tests, 99 functions, 198 assertions.

- **Engine:** an explicit frame stack replaces recursion ([ADR-0006](/decisions/adr-0006-expansion-uses-an-explicit-frame-stack--01a1d31ab339.md)).
- **Layout:** `src/functions.zig` holds the functions and glob matching. `src/database.zig` replays the statements and classifies targets.
- **Origins:** a `default` origin sits below `environment`. `MAKE` and `SHELL` use it. zmake ignores `SHELL` from the environment, as GNU Make does.
- **Loud failures:** unsupported GNU functions, suffix rules and unknown special targets give an error ([ADR-0005](/decisions/adr-0005-unsupported-directives-fail-loudly--01a1d30ae687.md)).
- **Difference:** the error for a recursive variable shows the line that uses the variable. GNU Make shows the line that defines it.
- **Check against GNU Make:** `$(patsubst %.c,%.o,x.c.c)` gives `x.c.o` in both tools.

## Related
[Architecture](/architecture/zmake-architecture-overview--01a1d30ae65a.md) · [PLAN.md](../../PLAN.md)
