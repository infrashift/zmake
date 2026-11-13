---
id: "01a1d30a-e694-70e2-9feb-c5b29fdf8ea2"
title: "ISSUE-002: Context-sensitive lexer and dual-mode parser"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-2"
  - "lexer"
  - "parser"
  - "closed"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T22:04:11-06:00"
description: "Phase 2: logical lines, recipe detection per mode, assignments, rules, pattern rules, special targets and task syntax."
---

# ISSUE-002: Context-sensitive lexer and dual-mode parser

**Status/Phase:** Closed · Phase 2

## Description
Build `src/lexer.zig` and `src/parser.zig`. The parser produces a `Makefile` value for both modes.

## Acceptance Criteria
- [x] The lexer joins continuations, strips comments and detects recipe lines for each mode.
- [x] The parser reads `=`, `:=`, `::=`, `?=` and `+=`.
- [x] The parser reads rules, order-only prerequisites, pattern rules and inline `; recipe` text.
- [x] The parser reads `.PHONY` and `.DEFAULT_GOAL`.
- [x] Modern mode reads `@name:` and `task name:`. Legacy mode reads them as plain target names.
- [x] Unsupported directives fail with `file:line` ([ADR-0005](/decisions/adr-0005-unsupported-directives-fail-loudly--01a1d30ae687.md)).
- [x] `tests/legacy_test.zig` and `tests/modern_test.zig` cover both modes. `make lint test` passes.

## Resolution
Done on 2026-11-12. `make lint test` passes: 47 functions, 94 assertions.

- **Lexer contract:** `Lexer.next(in_rule)` takes the rule state from the parser. Only the parser knows when a rule is open.
- **Messages:** `Makefile:2: *** missing separator.  Stop.` matches GNU Make byte for byte. zmake omits its program name when a message starts with `file:line:`.
- **Scope:** double-colon rules, target-specific variables and `!=` fail with an error ([ADR-0005](/decisions/adr-0005-unsupported-directives-fail-loudly--01a1d30ae687.md)).
- **Modern blocks:** a recipe line with less indent than its block is an error ([spec](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md)).
- **Values:** zmake keeps trailing white space in variable values, as GNU Make does.

## Related
[Architecture](/architecture/zmake-architecture-overview--01a1d30ae65a.md) · [PLAN.md](../../PLAN.md)
