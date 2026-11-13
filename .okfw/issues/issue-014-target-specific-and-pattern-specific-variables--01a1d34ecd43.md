---
id: "01a1d34e-cd43-7d09-9397-e07163daa653"
title: "ISSUE-014: Target-specific and pattern-specific variables"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-14"
  - "eval"
  - "open"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:08:39-06:00"
description: "Phase 14: target-specific and pattern-specific variables, inherited by prerequisites."
---

# ISSUE-014: Target-specific and pattern-specific variables

**Status/Phase:** Open · Phase 14

## Description
`target: VAR = value` sets a variable for the recipe of the target and for the prerequisites that it builds.

## Acceptance Criteria
- [ ] All assignment operators, `override` and `export` in a target-specific assignment.
- [ ] Pattern-specific variables: `%.o: CFLAGS += -g`.
- [ ] A prerequisite inherits the values of the target that first needs it. `private` stops the inheritance.
- [ ] `make check` passes.

## Related
[PLAN.md](../../PLAN.md)
