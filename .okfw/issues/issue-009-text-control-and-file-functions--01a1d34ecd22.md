---
id: "01a1d34e-cd22-7eb2-8a84-5076ded43cc8"
title: "ISSUE-009: Text, control and file functions"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-9"
  - "functions"
  - "closed"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:27:52-06:00"
description: "Phase 9: the GNU Make functions beyond subst, patsubst, wildcard and shell, on the frame stack without recursion."
---

# ISSUE-009: Text, control and file functions

**Status/Phase:** Closed · Phase 9

## Description
Implement the GNU Make functions that zmake rejects today. Keep the frame stack of [ADR-0006](/decisions/adr-0006-expansion-uses-an-explicit-frame-stack--01a1d31ab339.md): no recursion. `eval` comes with the reader in Phase 10. `guile` stays unsupported.

## Acceptance Criteria
- [x] Text functions: `filter`, `filter-out`, `findstring`, `sort`, `strip`, `word`, `words`, `wordlist`, `firstword`, `lastword`.
- [x] File name functions: `dir`, `notdir`, `suffix`, `basename`, `addsuffix`, `addprefix`, `join`, `abspath`, `realpath`.
- [x] Control functions: `if`, `or`, `and`, `foreach`, `call`, `let`, `intcmp`. `if`, `and` and `or` expand only the arguments that they need.
- [x] Variable functions: `value`, `origin`, `flavor`. Message functions: `error`, `warning`, `info`. The `file` function.
- [x] Each function matches GNU Make 4.3 output in `tests/acceptance.sh`.
- [x] `make check` passes.

## Resolution
Done on 2026-11-12 in Phase 9. `make check` passes: 83 unit tests, 64 acceptance checks, 203 functions with 406 assertions.

- All GNU Make functions except `eval` (Phase 10) and `guile` (unsupported). [ADR-0011](/decisions/adr-0011-lazy-functions-use-staged-calls-on-the-frame-stack--01a1d35f6009.md) records the design.
- `src/textfns.zig` holds the pure functions. `src/builtins.zig` applies the eager ones. The evaluator runs `if`, `and`, `or`, `intcmp`, `foreach`, `let` and `call` in stages on its frame stack, with no recursion.
- Acceptance scenario 10 runs one Makefile with each function through GNU Make 4.3 and zmake. The output is the same byte for byte. `let` and `intcmp` (GNU Make 4.4) have their own checks.
- A line with only an expansion, such as `$(info text)`, is now valid when the expansion is empty.
- Scenario 5 now checks `$(guile ...)` for the unsupported-function error, because `foreach` works.

## Related
[PLAN.md](../../PLAN.md)
