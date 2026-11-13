---
id: "01a1d30a-e65a-79cc-94c7-fd6eda02e5d6"
title: "zmake architecture overview"
type: "Architecture"
tags:
  - "architecture"
  - "overview"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "The zmake pipeline from input file to shell: modules, data flow, memory model and the two expansion phases."
---

# zmake architecture overview

**Status:** Draft. Phases 1–5 build it. See [ISSUE-001](/issues/issue-001-scaffolding-ast-and-input-file-discovery--01a1d30ae68d.md) to [ISSUE-005](/issues/issue-005-parallel-executor-and-gnu-make-jobserver--01a1d30ae6a7.md).

## Pipeline
```
input file → lexer → parser → AST → evaluator → DAG → executor → /bin/sh
                                                         ↕
                                                     jobserver
```

## Modules
| Module | Responsibility |
|---|---|
| `src/main.zig` | Calls the library modules in sequence. Prints errors and sets the exit code. |
| `src/cli.zig` | Parses the options and `VAR=value` overrides. Selects the input file and its syntax mode. |
| `src/diag.zig` | Holds a fixed-size error message. Zig errors carry no payload, so each module writes the text here. |
| `src/ast.zig` | Holds the data types: `SyntaxMode`, `TargetKind`, `VariableFlavor`, `Variable`, `RecipeLine`, `Rule`, `Makefile`. |
| `src/lexer.zig` | Splits the input file into logical lines. Joins continuations, strips comments and marks recipe lines. |
| `src/parser.zig` | Turns logical lines into rules, assignments and special targets. Applies the mode-specific syntax. |
| `src/eval.zig` | Keeps the variable table. Expands variables, automatic variables and functions on a frame stack ([ADR-0006](/decisions/adr-0006-expansion-uses-an-explicit-frame-stack--01a1d31ab339.md)). |
| `src/functions.zig` | Implements `subst`, `patsubst`, `wildcard`, `shell`, substitution references and glob matching. |
| `src/database.zig` | Replays the statements through the evaluator. Collects the expanded rules and the special targets. Classifies each target. |
| `src/dag.zig` | Resolves each goal through explicit rules, pattern rules and existing files. Detects cycles with a three-color search on an explicit stack. Sorts the graph. |
| `src/executor.zig` | Decides which targets are out of date. Runs recipe lines through `/bin/sh -c`. Schedules jobs. |
| `src/jobserver.zig` | Holds the GNU-compatible token pool for `-j`. |

## Memory
One arena holds all memory for one invocation ([ADR-0003](/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md)). zmake frees nothing before exit. Hard limits cap the input file size, the expansion depth and the graph size.

## Two expansion phases
- **Immediate:** the parser expands `:=` values, target names and prerequisite lists when it reads the line.
- **Deferred:** the evaluator expands `=` values and recipe lines before the executor runs them.

## Related
[Syntax modes and target kinds](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md) · [CLI contract](/specs/cli-contract--01a1d30ae665.md) · [Jobserver protocol](/specs/jobserver-protocol--01a1d30ae66b.md)
