---
id: "01a1d34e-cd29-798c-b3a4-f14c3caa9d03"
title: "ISSUE-010: Conditionals, define, override, undefine and eval"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-10"
  - "reader"
  - "open"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:08:39-06:00"
description: "Phase 10: a reader that evaluates conditionals and multi-line definitions while it reads the input file."
---

# ISSUE-010: Conditionals, define, override, undefine and eval

**Status/Phase:** Open · Phase 10

## Description
Conditionals need the variables defined so far, so the reader must evaluate each statement as it reads it. Move the read loop from `parser.parse` into a reader that drives the lexer, the parser and the evaluator together.

## Acceptance Criteria
- [ ] `ifeq`, `ifneq`, `ifdef`, `ifndef`, `else` (also `else ifeq ...`) and `endif`, with an explicit nesting stack and a depth limit.
- [ ] Conditionals inside a recipe select recipe lines, as in GNU Make.
- [ ] A skipped branch does not report syntax errors, except for the nesting of conditionals.
- [ ] `define NAME [=|:=|::=|?=|+=]` ... `endef`, nested `define` blocks, and `override define`.
- [ ] `override` assignments win over command-line variables. `undefine NAME`.
- [ ] `$(eval text)` at read time. `eval` in a recipe stops with an error.
- [ ] `make check` passes.

## Related
[PLAN.md](../../PLAN.md)
