---
id: "01a1d30a-e6a0-7c26-96b4-6b7e174f0eb7"
title: "ISSUE-004: Dependency graph, pattern rules and cycle detection"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-4"
  - "dag"
  - "closed"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T22:15:10-06:00"
description: "Phase 4: goal resolution through explicit rules, pattern rules and files, cycle detection with line numbers, topological order."
---

# ISSUE-004: Dependency graph, pattern rules and cycle detection

**Status/Phase:** Closed · Phase 4

## Description
Build `src/dag.zig` with an explicit stack ([ADR-0003](/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md)).

## Acceptance Criteria
- [x] Explicit rules for one target merge their prerequisites. The last recipe wins with a warning.
- [x] Pattern rules match in definition order. The stem replaces `%` in the prerequisites.
- [x] A missing prerequisite with no rule gives the GNU message.
- [x] A cycle gives an error that shows the path with `file:line` for each rule.
- [x] `make lint test` passes.

## Resolution
Done on 2026-11-12. `make lint test` passes: 68 tests, 119 functions, 238 assertions.

- **Search:** a three-color DFS on an explicit stack builds the order and the deduplicated `deps` of each node. The graph holds at most 65,536 nodes and 1,024 levels.
- **Pattern rules:** the shortest stem wins, with one level of chaining. An explicit rule without a recipe takes the recipe of a pattern rule ([spec](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md)).
- **Messages:** `No rule to make target` and the overriding-recipe warnings match GNU Make byte for byte. The warnings use the line of the first recipe line, as GNU Make does.
- **Difference:** a cycle is an error. GNU Make drops the edge with a warning.

## Related
[Architecture](/architecture/zmake-architecture-overview--01a1d30ae65a.md) · [PLAN.md](../../PLAN.md)
