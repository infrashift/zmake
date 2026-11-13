---
id: "01a1d30a-e68d-7d67-b114-b737e130faed"
title: "ISSUE-001: Scaffolding, AST and input file discovery"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-1"
  - "ast"
  - "cli"
  - "closed"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:59:19-06:00"
description: "Phase 1: build.zig, the AST types, input file discovery, mode selection and the CLI options."
---

# ISSUE-001: Scaffolding, AST and input file discovery

**Status/Phase:** Closed · Phase 1

## Description
Create the Zig project, the AST types in `src/ast.zig` and the CLI in `src/main.zig`.

## Acceptance Criteria
- [x] `build.zig` has the steps `install`, `test` and `acceptance`. `build.zig.zon` pins Zig 0.17.1.
- [x] `src/ast.zig` defines `SyntaxMode`, `TargetKind`, `VariableFlavor`, `Variable`, `RecipeLine`, `Rule` and `Makefile`.
- [x] `src/main.zig` finds the input file in the order of the [Syntax modes](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md) spec.
- [x] The options `-f`, `-C`, `-j`, `-n`, `--modern`, `--legacy` and `VAR=value` parse. See the [CLI contract](/specs/cli-contract--01a1d30ae665.md).
- [x] `make lint test` passes.

## Resolution
Done on 2026-11-12. `make lint test` passes: 17 tests, 20 functions, 40 assertions.

- **Layout:** argument parsing and discovery live in `src/cli.zig`, so `src/main.zig` stays thin. `src/diag.zig` carries error messages.
- **AST:** the parser emits `Statement` values in file order. The evaluator replays them, so immediate expansion sees only earlier definitions.
- **Zig 0.17:** the `**` array operator is gone. Use `@splat`. `std.testing.io` gives the tests an `Io`.
- **Lint:** R7 now also rejects `else |_| {}`. Test helpers are exempt from R4 and R5 ([ADR-0003](/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md)).

## Related
[Architecture](/architecture/zmake-architecture-overview--01a1d30ae65a.md) · [PLAN.md](../../PLAN.md)
