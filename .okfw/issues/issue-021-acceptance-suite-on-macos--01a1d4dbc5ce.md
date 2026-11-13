---
id: "01a1d4db-c5ce-7213-a476-229fcd3fa503"
title: "ISSUE-021: Acceptance suite on macOS"
type: "issue"
kind: "issue"
tags:
  - "issue"
  - "follow-up"
  - "ci"
  - "platforms"
  - "closed"
created: "2026-11-13T06:22:15-06:00"
timestamp: "2026-11-13T06:40:54-06:00"
description: "CI builds GNU Make 4.3 on macOS and runs the acceptance suite there; the script uses only portable commands."
---

# ISSUE-021: Acceptance suite on macOS

**Status/Phase:** Closed · Phase 21

## Description
CI runs only the unit tests on macOS ([ADR-0021](/decisions/adr-0021-ci-runs-every-gate-on-linux-and-the-unit-tests-on-macos--01a1d3a9a48c.md)). The acceptance suite compares the output of zmake with GNU Make 4.3, but macOS has GNU Make 3.81. The script also uses commands that differ on BSD systems, for example `date +%s%N` and `paste -s` without a file.

## Acceptance Criteria
- [x] The macOS jobs build GNU Make 4.3 from the GNU release, with a pinned SHA-256 sum.
- [x] The acceptance suite runs on macOS arm64 and x86_64 and compares the output with GNU Make 4.3.
- [x] The script uses only commands that work on Linux, macOS and FreeBSD.
- [x] A check that needs Linux behavior tests the documented macOS behavior instead.
- [x] `make check` passes on Linux, and CI passes on all jobs.

## Resolution
Done on 2026-11-13 in Phase 21. `make check` passes, and CI passes on Linux and on macOS arm64 and x86_64 ([ADR-0023](/decisions/adr-0023-the-acceptance-suite-runs-on-macos-against-gnu-make-4-3--01a1d4ecd992.md)).

- The macOS jobs build GNU Make 4.3 from the GNU release with a pinned SHA-256 sum. The acceptance suite gives 107 passed, 0 failed on both runners.
- The script uses no GNU-only options. It reads the time from `$EPOCHREALTIME` or Python, and it gives `paste` the file `-`.
- Off Linux, the script checks the documented `-j1` warning in a GNU Make pipe pool.
- Found during the phase: on macOS, zmake read `Makefile` as `makefile` and found `util.C` for `util.c`. New `src/dircache.zig` checks the exact case through directory listings, as GNU Make does.
- The unit test of the input file search compares the exact name again. Commit 320d2bc had made it ignore case on a wrong assumption.

## Related
[ADR-0020](/decisions/adr-0020-a-named-fifo-shares-the-jobserver-off-linux--01a1d399e000.md) · [ADR-0021](/decisions/adr-0021-ci-runs-every-gate-on-linux-and-the-unit-tests-on-macos--01a1d3a9a48c.md) · [PLAN.md](../../PLAN.md)
