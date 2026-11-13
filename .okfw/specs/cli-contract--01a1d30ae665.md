---
id: "01a1d30a-e665-7b95-853a-a86d1d4f1843"
title: "CLI contract"
type: "Spec"
tags:
  - "spec"
  - "cli"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "The zmake command line: options, input file discovery, variable overrides, messages and exit codes."
---

# CLI contract

# CLI contract

**Status:** Draft. [ISSUE-001](/issues/issue-001-scaffolding-ast-and-input-file-discovery--01a1d30ae68d.md) and [ISSUE-005](/issues/issue-005-parallel-executor-and-gnu-make-jobserver--01a1d30ae6a7.md) build it in `src/main.zig`.

## Usage
`zmake [options] [VAR=value ...] [target ...]`

## Options
| Option | Effect |
|---|---|
| `-f FILE` | Read FILE as the input file. The basename selects the mode. |
| `-C DIR` | Change to DIR before zmake reads the input file. |
| `-j N`, `-jN` | Run up to N jobs at the same time. |
| `-n` | Print the recipe lines. Do not run them. |
| `--modern` | Use modern mode for any input file. |
| `--legacy` | Use legacy mode for any input file. |
| `-h`, `--help` | Print the usage and exit. |

An argument with `=` sets a variable. A command-line variable overrides the input file and the environment.

## Default goal
zmake builds the targets on the command line. With no target, it builds `.DEFAULT_GOAL`. Without `.DEFAULT_GOAL`, it builds the first target that does not start with `.` and is not a pattern.

## Messages
zmake uses the GNU Make message forms:
- `zmake: 'app' is up to date.`
- `zmake: Nothing to be done for 'all'.`
- `zmake: *** No rule to make target 'x', needed by 'y'.  Stop.`
- `zmake: *** [Makefile:12: app] Error 1`

## Exit codes
| Code | Meaning |
|---|---|
| 0 | Success. |
| 2 | A usage error, a parse error, a missing rule, a cycle or a failed recipe line. |
