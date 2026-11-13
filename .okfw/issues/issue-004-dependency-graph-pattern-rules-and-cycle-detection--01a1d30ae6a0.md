---
id: "01a1d30a-e6a0-7c26-96b4-6b7e174f0eb7"
title: "ISSUE-004: Dependency graph, pattern rules and cycle detection"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "open"
  - "phase-4"
  - "dag"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "Phase 4: goal resolution through explicit rules, pattern rules and files, cycle detection with line numbers, topological order."
---

# ISSUE-004: Dependency graph, pattern rules and cycle detection

# ISSUE-004: Dependency graph, pattern rules and cycle detection

**Status/Phase:** Open · Phase 4

## Description
Build `src/dag.zig` with an explicit stack ([ADR-0003](/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md)).

## Acceptance Criteria
- [ ] Explicit rules for one target merge their prerequisites. The last recipe wins with a warning.
- [ ] Pattern rules match in definition order. The stem replaces `%` in the prerequisites.
- [ ] A missing prerequisite with no rule gives the GNU message.
- [ ] A cycle gives an error that shows the path with `file:line` for each rule.
- [ ] `make lint test` passes.

## Related
[Architecture](/architecture/zmake-architecture-overview--01a1d30ae65a.md) · [PLAN.md](../../PLAN.md)
