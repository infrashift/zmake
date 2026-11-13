---
id: "01a1d34e-cd4a-7bfd-ae01-c9c41da3386e"
title: "ISSUE-015: Double-colon rules"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-15"
  - "dag"
  - "open"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:08:39-06:00"
description: "Phase 15: double-colon rules, each with an independent recipe."
---

# ISSUE-015: Double-colon rules

**Status/Phase:** Open · Phase 15

## Description
A target with `::` rules runs each rule whose prerequisites are newer, in file order.

## Acceptance Criteria
- [ ] `a:: b` rules for one target run independently, in file order.
- [ ] A double-colon rule with no prerequisites always runs.
- [ ] A mix of `:` and `::` rules for one target is an error, as in GNU Make.
- [ ] `make check` passes.

## Related
[PLAN.md](../../PLAN.md)
