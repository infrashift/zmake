---
id: "01a1d34e-cd67-72c2-beef-7f7331f823c7"
title: "ISSUE-019: Jobserver on macOS and the BSDs"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-19"
  - "jobserver"
  - "closed"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-13T00:30:39-06:00"
description: "Phase 19: the jobserver and the build without Linux-only system calls."
---

# ISSUE-019: Jobserver on macOS and the BSDs

**Status/Phase:** Closed · Phase 19

## Description
The jobserver reopens `/proc/self/fd/R` and calls `pipe2`. Other systems lack both.

## Acceptance Criteria
- [x] zmake builds for macOS and FreeBSD (cross-compile check).
- [x] The jobserver uses a portable way to take a token without a block.
- [x] Linux keeps the design of ADR-0008.
- [x] `make check` passes.

## Resolution
Done on 2026-11-13 in Phase 19. `make check` passes, with the new `cross` gate.

- Off Linux, a new jobserver is a named fifo, as in GNU Make 4.4. Linux keeps the pipe of ADR-0008 ([ADR-0020](/decisions/adr-0020-a-named-fifo-shares-the-jobserver-off-linux--01a1d399e000.md)).
- `--jobserver-style=fifo|pipe` selects the style. Acceptance scenario 20 runs the fifo server, a recursive zmake on the fifo pool, and the cleanup, on Linux.
- A client off Linux, or without `/proc`, cannot share a pipe pool. It warns and uses `-j1`.
- `make cross` builds for macOS and FreeBSD on arm64 and x86_64. Before this phase, the macOS build failed (no `pipe2`), and `-j` failed at run time on FreeBSD without `/proc`.
- Not verified: a test run on macOS or FreeBSD. This system runs Linux only.
- Found during the phase: a static pattern rule gave a confusing error. It now stops with a clear message, and [ISSUE-020](/issues/issue-020-static-pattern-rules--01a1d399e029.md) tracks support.

## Related
[PLAN.md](../../PLAN.md)
