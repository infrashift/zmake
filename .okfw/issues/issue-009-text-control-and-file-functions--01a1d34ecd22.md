---
id: "01a1d34e-cd22-7eb2-8a84-5076ded43cc8"
title: "ISSUE-009: Text, control and file functions"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-9"
  - "functions"
  - "open"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:08:39-06:00"
description: "Phase 9: the GNU Make functions beyond subst, patsubst, wildcard and shell, on the frame stack without recursion."
---

# ISSUE-009: Text, control and file functions

**Status/Phase:** Open · Phase 9

## Description
Implement the GNU Make functions that zmake rejects today. Keep the frame stack of [ADR-0006](/decisions/adr-0006-expansion-uses-an-explicit-frame-stack--01a1d31ab339.md): no recursion. `eval` comes with the reader in Phase 10. `guile` stays unsupported.

## Acceptance Criteria
- [ ] Text functions: `filter`, `filter-out`, `findstring`, `sort`, `strip`, `word`, `words`, `wordlist`, `firstword`, `lastword`.
- [ ] File name functions: `dir`, `notdir`, `suffix`, `basename`, `addsuffix`, `addprefix`, `join`, `abspath`, `realpath`.
- [ ] Control functions: `if`, `or`, `and`, `foreach`, `call`, `let`, `intcmp`. `if`, `and` and `or` expand only the arguments that they need.
- [ ] Variable functions: `value`, `origin`, `flavor`. Message functions: `error`, `warning`, `info`. The `file` function.
- [ ] Each function matches GNU Make 4.3 output in `tests/acceptance.sh`.
- [ ] `make check` passes.

## Related
[PLAN.md](../../PLAN.md)
