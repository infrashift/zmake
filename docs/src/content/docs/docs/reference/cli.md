---
title: CLI
description: The zmake command line, with its options, environment, default goal, messages and exit codes.
---

```text
zmake [options] [VAR=value ...] [target ...]
```

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

An argument with `=` sets a variable. A command-line variable overrides the
input file and the environment.

## Input file discovery

Without `-f`, zmake searches the directory in this order: `ZMakefile`,
`Make.zig.mk`, `GNUmakefile`, `makefile`, `Makefile`. See
[Syntax Modes](../../guides/syntax-modes/).

## Environment

- zmake reads `MAKEFLAGS` from a parent make: the `n` flag, `-jN`, `--jobserver-auth`, `--jobserver-fds` and `-- VAR=value` overrides.
- Each recipe line gets `MAKEFLAGS` with the same forms, and `MAKELEVEL` plus one.
- A line with `+` or with `$(MAKE)` also runs under `-n`.
- zmake ignores `SHELL` from the environment. Set `SHELL` in the input file to change the shell.
- `export` and `unexport` change the environment of each recipe line. See [Export and the Environment](../../guides/export/).

## Recipe lines

Each recipe line runs in its own `/bin/sh -c`. A line can start with these
prefixes:

| Prefix | Effect |
|---|---|
| `@` | Do not echo the line. |
| `-` | Ignore a failure of the line. |
| `+` | Run the line also under `-n`. |

A line with `-` that fails prints a message, and the recipe continues:

```text
zmake: [Makefile:3: all] Error 1 (ignored)
```

## Default goal

zmake builds the targets on the command line. With no target, it builds
`.DEFAULT_GOAL`. Without `.DEFAULT_GOAL`, it builds the first target that does
not start with `.` and is not a pattern.

## Messages

zmake uses the GNU Make message forms:

```text
zmake: 'app' is up to date.
zmake: Nothing to be done for 'all'.
zmake: *** No rule to make target 'x', needed by 'y'.  Stop.
zmake: *** [Makefile:12: app] Error 1
zmake: *** Deleting file 'out'
Makefile:2: *** missing separator.  Stop.
```

A message that starts with `file:line:` has no program name.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success. |
| 2 | A usage error, a parse error, a missing rule, a cycle or a failed recipe line. |
