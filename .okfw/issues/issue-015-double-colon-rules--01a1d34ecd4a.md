---
id: "01a1d34e-cd4a-7bfd-ae01-c9c41da3386e"
title: "ISSUE-015: Double-colon rules"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-15"
  - "dag"
  - "closed"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-13T00:04:18-06:00"
description: "Phase 15: double-colon rules, each with an independent recipe."
---

# ISSUE-015: Double-colon rules

**Status/Phase:** Closed · Phase 15

## Description
A target with `::` rules runs each rule whose prerequisites are newer, in file order.

## Acceptance Criteria
- [x] `a:: b` rules for one target run independently, in file order.
- [x] A double-colon rule with no prerequisites always runs.
- [x] A mix of `:` and `::` rules for one target is an error, as in GNU Make.
- [x] `make check` passes.

## Resolution
Done on 2026-11-13 in Phase 15. `make check` passes: 95 unit tests, 90 acceptance checks.

- Double-colon rules work. Each rule is an instance on the graph node, and the executor decides and runs each one on its own, in file order ([ADR-0017](/decisions/adr-0017-a-double-colon-target-keeps-one-instance-per-rule--01a1d38105ef.md)).
- A mix of `:` and `::` rules gives the GNU Make error at the line of the second rule. A double-colon pattern rule is an error.
- Bug found and fixed: zmake printed "is up to date" for all goals at the end. GNU Make prints it when the goal is done, before the next goal starts. zmake now does the same.
- Acceptance scenario 16 matches GNU Make 4.3 in six cases.

## Related
[PLAN.md](../../PLAN.md)
