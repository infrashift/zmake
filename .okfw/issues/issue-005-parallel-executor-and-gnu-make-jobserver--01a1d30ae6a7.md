---
id: "01a1d30a-e6a7-7338-a296-8216af8a4d8c"
title: "ISSUE-005: Parallel executor and GNU Make jobserver"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "open"
  - "phase-5"
  - "executor"
  - "jobserver"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "Phase 5: out-of-date checks, recipe execution, -j scheduling, the jobserver, and the acceptance scenarios."
---

# ISSUE-005: Parallel executor and GNU Make jobserver

**Status/Phase:** Open · Phase 5

## Description
Build `src/executor.zig` and `src/jobserver.zig`. Add `tests/acceptance.sh`.

## Acceptance Criteria
- [ ] File targets rebuild when they are missing or older than a prerequisite. Phony targets always run.
- [ ] Each recipe line runs in its own `/bin/sh -c`. The prefixes `@`, `-` and `+` work. `-n` prints only.
- [ ] A failed recipe line deletes a partial file target and gives exit code 2.
- [ ] `-jN` runs up to N jobs. The [Jobserver protocol](/specs/jobserver-protocol--01a1d30ae66b.md) works as server and as client.
- [ ] Acceptance: the `build/` directory scenario passes in modern mode.
- [ ] Acceptance: `@deploy: build` with 4-space indentation runs `build`, then `deploy`.
- [ ] Acceptance: the legacy C project rebuilds only dirty objects and respects `.PHONY`.
- [ ] `make check` passes.

## Related
[Architecture](/architecture/zmake-architecture-overview--01a1d30ae65a.md) · [PLAN.md](../../PLAN.md)
