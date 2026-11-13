---
id: "01a1d34e-cd67-72c2-beef-7f7331f823c7"
title: "ISSUE-019: Jobserver on macOS and the BSDs"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-19"
  - "jobserver"
  - "open"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:08:39-06:00"
description: "Phase 19: the jobserver and the build without Linux-only system calls."
---

# ISSUE-019: Jobserver on macOS and the BSDs

**Status/Phase:** Open · Phase 19

## Description
The jobserver reopens `/proc/self/fd/R` and calls `pipe2`. Other systems lack both.

## Acceptance Criteria
- [ ] zmake builds for macOS and FreeBSD (cross-compile check).
- [ ] The jobserver uses a portable way to take a token without a block.
- [ ] Linux keeps the design of ADR-0008.
- [ ] `make check` passes.

## Related
[PLAN.md](../../PLAN.md)
