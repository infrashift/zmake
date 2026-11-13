---
id: "01a1d34e-cd43-7d09-9397-e07163daa653"
title: "ISSUE-014: Target-specific and pattern-specific variables"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-14"
  - "eval"
  - "closed"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:59:04-06:00"
description: "Phase 14: target-specific and pattern-specific variables, inherited by prerequisites."
---

# ISSUE-014: Target-specific and pattern-specific variables

**Status/Phase:** Closed · Phase 14

## Description
`target: VAR = value` sets a variable for the recipe of the target and for the prerequisites that it builds.

## Acceptance Criteria
- [x] All assignment operators, `override` and `export` in a target-specific assignment.
- [x] Pattern-specific variables: `%.o: CFLAGS += -g`.
- [x] A prerequisite inherits the values of the target that first needs it. `private` stops the inheritance.
- [x] `make check` passes.

## Resolution
Done on 2026-11-12 in Phase 14. `make check` passes: 94 unit tests, 89 acceptance checks.

- Target-specific and pattern-specific variables work with all assignment operators and the `override`, `export` and `private` modifiers ([ADR-0016](/decisions/adr-0016-target-contexts-are-layers-that-a-pre-pass-builds--01a1d37ca0dc.md)).
- `src/context.zig` builds the layers of each node before the first job. A node gets the layers of its first parent without `private` variables. Then it adds its own pattern and target assignments.
- `Evaluator.lookup` reads the layers first. The executor sets them for the recipe and the environment of each job.
- Bug found and fixed: a serial build started all leaves first. It now runs in the depth-first post-order of GNU Make, through a priority queue on the position in `graph.order`.
- Acceptance scenario 15 compares values, inheritance and run order with GNU Make 4.3. All match.

## Related
[PLAN.md](../../PLAN.md)
