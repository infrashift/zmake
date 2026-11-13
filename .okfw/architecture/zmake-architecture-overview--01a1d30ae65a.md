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
input file → reader (lexer → parser → evaluator) → database → DAG → executor → /bin/sh
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
| `src/textfns.zig` | Implements the pure text and file name functions, for example `filter`, `sort`, `word`, `dir` and `abspath`. |
| `src/builtins.zig` | Applies the eager functions to their expanded arguments. The evaluator handles the lazy ones on its frame stack ([ADR-0011](/decisions/adr-0011-lazy-functions-use-staged-calls-on-the-frame-stack--01a1d35f6009.md)). |
| `src/reader.zig` | Reads the input file line by line and applies each statement at once. Handles the conditionals, `define`, `override`, `undefine` and the queued `$(eval ...)` texts on explicit stacks ([ADR-0012](/decisions/adr-0012-a-reader-evaluates-each-statement-while-it-reads--01a1d36899c8.md)). |
| `src/database.zig` | Replays the statements through the evaluator. Collects the expanded rules and the special targets. Classifies each target. |
| `src/dag.zig` | Resolves each goal through explicit rules, pattern rules and existing files. Detects cycles with a three-color search on an explicit stack. Sorts the graph. |
| `src/executor.zig` | Decides which targets are out of date. Expands each recipe before its first line runs. Runs recipe lines through `/bin/sh -c`. Schedules jobs on `Io` tasks. |
| `src/jobserver.zig` | Holds the GNU-compatible token pool for `-j` ([ADR-0008](/decisions/adr-0008-take-jobserver-tokens-through-a-private-non-blocking-descriptor--01a1d327df28.md)). Reads and writes `MAKEFLAGS`. |

## Memory
One arena holds all memory for one invocation ([ADR-0003](/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md)). zmake frees nothing before exit. Hard limits cap the input file size, the expansion depth and the graph size.

## Threads
The scheduler runs on the main thread. It owns the node state and the evaluator. Each job runs on a concurrent `Io` task. A worker only runs commands, prints under the output lock and queues its completion under the mutex.

## Two expansion phases
- **Immediate:** the parser expands `:=` values, target names and prerequisite lists when it reads the line.
- **Deferred:** the evaluator expands `=` values and recipe lines before the executor runs them.

## Related
[Syntax modes and target kinds](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md) · [CLI contract](/specs/cli-contract--01a1d30ae665.md) · [Jobserver protocol](/specs/jobserver-protocol--01a1d30ae66b.md)
