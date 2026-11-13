---
id: "01a1d30a-e694-70e2-9feb-c5b29fdf8ea2"
title: "ISSUE-002: Context-sensitive lexer and dual-mode parser"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "open"
  - "phase-2"
  - "lexer"
  - "parser"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "Phase 2: logical lines, recipe detection per mode, assignments, rules, pattern rules, special targets and task syntax."
---

# ISSUE-002: Context-sensitive lexer and dual-mode parser

# ISSUE-002: Context-sensitive lexer and dual-mode parser

**Status/Phase:** Open · Phase 2

## Description
Build `src/lexer.zig` and `src/parser.zig`. The parser produces a `Makefile` value for both modes.

## Acceptance Criteria
- [ ] The lexer joins continuations, strips comments and detects recipe lines for each mode.
- [ ] The parser reads `=`, `:=`, `::=`, `?=` and `+=`.
- [ ] The parser reads rules, order-only prerequisites, pattern rules and inline `; recipe` text.
- [ ] The parser reads `.PHONY` and `.DEFAULT_GOAL`.
- [ ] Modern mode reads `@name:` and `task name:`. Legacy mode reads them as plain target names.
- [ ] Unsupported directives fail with `file:line` ([ADR-0005](/decisions/adr-0005-unsupported-directives-fail-loudly--01a1d30ae687.md)).
- [ ] `tests/legacy_test.zig` and `tests/modern_test.zig` cover both modes. `make lint test` passes.

## Related
[Architecture](/architecture/zmake-architecture-overview--01a1d30ae65a.md) · [PLAN.md](../../PLAN.md)
