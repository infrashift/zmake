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
| `-r` | Add no built-in implicit rules ([ADR-0018](/decisions/adr-0018-built-in-rules-come-from-gnu-make-and-follow-the-suffix-list--01a1d38a371f.md)). |
| `-R` | Define no built-in variables. Implies `-r`. |
| `-k` | Keep going after a failure ([ADR-0019](/decisions/adr-0019-letter-flags-share-one-table-for-options-and-makeflags--01a1d390363b.md)). |
| `-q` | Run nothing. Exit 1 when a goal is out of date. |
| `-t` | Touch the out-of-date file targets. |
| `-B` | Treat every target as out of date. |
| `-s` | Do not echo the recipe lines. |
| `--modern` | Use modern mode for any input file. |
| `--legacy` | Use legacy mode for any input file. |
| `-h`, `--help` | Print the usage and exit. |

An argument with `=` sets a variable. A command-line variable overrides the input file and the environment.

## Environment
- zmake reads `MAKEFLAGS` from a parent make: the `n` flag, `-jN`, `--jobserver-auth`, `--jobserver-fds` and `-- VAR=value` overrides.
- Each recipe line gets `MAKEFLAGS` with the same forms, and `MAKELEVEL` plus one.
- A line with `+` or with `$(MAKE)` also runs under `-n`. The sub-make gets `n` in `MAKEFLAGS`, so it prints only.
- zmake ignores `SHELL` from the environment. Set `SHELL` in the input file to change the shell.
- Each recipe line also gets the exported variables. These are the `export` names, the command-line variables and the changed environment variables. With `export` alone, each file variable with a valid shell name also goes. `unexport` names stay out ([ADR-0014](/decisions/adr-0014-export-flags-decide-the-recipe-environment--01a1d37290f3.md)).

## Failed recipe lines
- A failed line stops the build. With `-j`, zmake prints `zmake: *** Waiting for unfinished jobs....` and waits for the running jobs.
- A line with `-` prints `zmake: [Makefile:3: all] Error 1 (ignored)` and the recipe continues.
- zmake deletes a partial file target by the rules of [ADR-0007](/decisions/adr-0007-delete-partial-targets-by-mode--01a1d327df21.md).

## Default goal
zmake builds the targets on the command line. With no target, it builds `.DEFAULT_GOAL`. Without `.DEFAULT_GOAL`, it builds the first target that does not start with `.` and is not a pattern.

## Messages
zmake uses the GNU Make message forms:
- `zmake: 'app' is up to date.`
- `zmake: Nothing to be done for 'all'.`
- `zmake: *** No rule to make target 'x', needed by 'y'.  Stop.`
- `zmake: *** [Makefile:12: app] Error 1`
- `Makefile:2: *** missing separator.  Stop.` (no program name when the message starts with `file:line:`)

## Exit codes
| Code | Meaning |
|---|---|
| 0 | Success. |
| 1 | Under `-q`: a goal is not up to date. |
| 2 | A usage error, a parse error, a missing rule, a cycle or a failed recipe line. |
