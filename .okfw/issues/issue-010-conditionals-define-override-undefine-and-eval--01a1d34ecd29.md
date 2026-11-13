---
id: "01a1d34e-cd29-798c-b3a4-f14c3caa9d03"
title: "ISSUE-010: Conditionals, define, override, undefine and eval"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-10"
  - "reader"
  - "closed"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:39:35-06:00"
description: "Phase 10: a reader that evaluates conditionals and multi-line definitions while it reads the input file."
---

# ISSUE-010: Conditionals, define, override, undefine and eval

**Status/Phase:** Closed · Phase 10

## Description
Conditionals need the variables defined so far, so the reader must evaluate each statement as it reads it. Move the read loop from `parser.parse` into a reader that drives the lexer, the parser and the evaluator together.

## Acceptance Criteria
- [x] `ifeq`, `ifneq`, `ifdef`, `ifndef`, `else` (also `else ifeq ...`) and `endif`, with an explicit nesting stack and a depth limit.
- [x] Conditionals inside a recipe select recipe lines, as in GNU Make.
- [x] A skipped branch does not report syntax errors, except for the nesting of conditionals.
- [x] `define NAME [=|:=|::=|?=|+=]` ... `endef`, nested `define` blocks, and `override define`.
- [x] `override` assignments win over command-line variables. `undefine NAME`.
- [x] `$(eval text)` at read time. `eval` in a recipe stops with an error.
- [x] `make check` passes.

## Resolution
Done on 2026-11-12 in Phase 10. `make check` passes: 89 unit tests, 75 acceptance checks, 239 functions with 479 assertions.

- `src/reader.zig` reads line by line and applies each statement at once ([ADR-0012](/decisions/adr-0012-a-reader-evaluates-each-statement-while-it-reads--01a1d36899c8.md)). `main.zig` uses it in place of `parser.parse` and `database.load`.
- Conditionals, `define`, `override`, `undefine` and read-time `$(eval ...)` work. Acceptance scenario 11 matches GNU Make 4.3, also the error messages.
- Bug found and fixed: a recipe line that expands to several lines ran in one shell. GNU Make runs each line as a command with its own prefixes and stops at a failed line. The executor now does the same. This makes canned recipes from `define` work.
- Difference: an eval takes effect after the statement that calls it. A recipe cannot call `eval`.
- `load` stays unsupported. Scenario 5 uses it for the unsupported-directive check.

## Related
[PLAN.md](../../PLAN.md)
