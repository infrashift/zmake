---
x-okfw-id: "01a1ec7f-6983-76d6-92e6-b7d7857daa3a"
title: "ISSUE-024: semscope in the lint target"
type: "Issue"
x-okfw-kind: "issue"
tags:
  - "issue"
  - "phase-24"
  - "lint"
  - "closed"
x-okfw-created: "2026-11-17T20:32:15-06:00"
x-okfw-timestamp: "2026-11-17T20:32:15-06:00"
description: "make lint runs semscope with the nasa-p10 ruleset when it is installed, and falls back to scripts/nasa-lint.py."
---

# ISSUE-024: semscope in the lint target

**Status/Phase:** Closed · Phase 24

## Description
semscope checks the ten Power of 10 rules of ADR-0003. `scripts/nasa-lint.py` checks six. On zmake `src/`, the two tools agree on the six shared rules. semscope also found one `@ptrCast` in `src/jobserver.zig` (R10).

## Acceptance Criteria
- [x] `make lint` and `zmake lint` run semscope when it is on the `PATH`, else `scripts/nasa-lint.py`.
- [x] `.semscope.cue` turns off NASA-P10-03 (the arena deviation of ADR-0003).
- [x] `src/jobserver.zig` has no `@ptrCast`.
- [x] A violation fails the task in both paths.
- [x] The dry runs of `lint` in the Makefile and the ZMakefile are the same.
- [x] The README, CLAUDE.md and the docs site name semscope.
- [x] `make check` and `zmake check` pass.

## Resolution
Done on 2026-11-17 in Phase 24 ([ADR-0026](/decisions/adr-0026-semscope-checks-the-power-of-10-rules--01a1ec7f697a.md)).

- The lint task of the Makefile and the ZMakefile runs `semscope scan -r nasa-p10 -r .semscope.cue --fail-level warning src` when `semscope` is on the `PATH`. Else it prints a note and runs `scripts/nasa-lint.py`. The dry runs of both files are the same.
- `src/jobserver.zig` passes `(&byte)[0..1]` to `write` and has no `@ptrCast`.
- A probe file with `while (true) {}` fails the task with semscope and with the fallback.
- On `src/`, semscope and `nasa-lint.py` report 306 functions and 614 assertions, and no findings.
- `make check`, `zmake check` and `make docs-build` pass.
