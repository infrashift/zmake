---
id: "01a1d30a-e68d-7d67-b114-b737e130faed"
title: "ISSUE-001: Scaffolding, AST and input file discovery"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "open"
  - "phase-1"
  - "ast"
  - "cli"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "Phase 1: build.zig, the AST types, input file discovery, mode selection and the CLI options."
---

# ISSUE-001: Scaffolding, AST and input file discovery

# ISSUE-001: Scaffolding, AST and input file discovery

**Status/Phase:** Open · Phase 1

## Description
Create the Zig project, the AST types in `src/ast.zig` and the CLI in `src/main.zig`.

## Acceptance Criteria
- [ ] `build.zig` has the steps `install`, `test` and `acceptance`. `build.zig.zon` pins Zig 0.17.1.
- [ ] `src/ast.zig` defines `SyntaxMode`, `TargetKind`, `VariableFlavor`, `Variable`, `RecipeLine`, `Rule` and `Makefile`.
- [ ] `src/main.zig` finds the input file in the order of the [Syntax modes](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md) spec.
- [ ] The options `-f`, `-C`, `-j`, `-n`, `--modern`, `--legacy` and `VAR=value` parse. See the [CLI contract](/specs/cli-contract--01a1d30ae665.md).
- [ ] `make lint test` passes.

## Related
[Architecture](/architecture/zmake-architecture-overview--01a1d30ae65a.md) · [PLAN.md](../../PLAN.md)
