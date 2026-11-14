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
| `-r` | Do not use the built-in implicit rules. |
| `-R` | Do not define the built-in variables. Implies `-r`. |
| `-k`, `--keep-going` | After a failure, build the other targets that do not need the failed one. |
| `-q`, `--question` | Run nothing. The exit code is 0 when the goals are up to date, else 1. |
| `-t`, `--touch` | Set the time of each out-of-date file target to now. Run no recipe. |
| `-B`, `--always-make` | Treat every target as out of date. |
| `-s`, `--silent` | Do not echo the recipe lines. |
| `--jobserver-style=fifo\|pipe` | The style of a new jobserver. Default: `pipe` on Linux, `fifo` elsewhere. |
| `--modern` | Use modern mode for any input file. |
| `--legacy` | Use legacy mode for any input file. |
| `-h`, `--help` | Print the usage and exit. |
| `-v`, `--version` | Print the version line and exit. |

Short options can share one argument, for example `-kj4` or `-sB`.

## Version line

`zmake --version` and `zmake -v` write one line to standard output and exit
with code 0. zmake reads no input file. It ignores the targets and the other
options, as GNU Make does.

```text
zmake 0.1.0 (5f983eac74b7e97bed690ab8c13815461bfa89f6)
```

- The version comes from `.version` in `build.zig.zon`.
- The commit is the output of `git rev-parse HEAD` when `zig build` runs.
- A `-dirty` suffix shows that a tracked file had a change at build time. A new file that git does not track does not add the suffix.
- A build without git or without a `.git` directory gives `unknown`, for example a build from a source tarball.

A script can compare the commit with a pinned value:

```sh
commit=$(zmake --version | sed -n 's/^zmake [^ ]* (\(.*\))$/\1/p')
[ "$commit" = "$pinned" ] || echo "zmake is not at $pinned"
```

An argument with `=` sets a variable. A command-line variable overrides the
input file and the environment.

## Input file discovery

Without `-f`, zmake searches the directory in this order: `ZMakefile`,
`Make.zig.mk`, `GNUmakefile`, `makefile`, `Makefile`. See
[Syntax Modes](../../guides/syntax-modes/).

## Environment

- zmake reads `MAKEFLAGS` from a parent make: the `B`, `k`, `n`, `q`, `r`, `R`, `s` and `t` flags, `-jN`, `--jobserver-auth`, `--jobserver-fds` and `-- VAR=value` overrides.
- Each recipe line gets `MAKEFLAGS` with the same forms, and `MAKELEVEL` plus one.
- In the `-- VAR=value` part, a backslash comes before each space, tab and backslash, as in GNU Make. So `zmake 'X=a b'` gives a sub-make `X=a b`, also through GNU Make.
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
zmake: Target 'all' not remade because of errors.
Makefile:2: *** missing separator.  Stop.
```

A message that starts with `file:line:` has no program name.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success. |
| 1 | Under `-q`: a goal is not up to date. |
| 2 | A usage error, a parse error, a missing rule, a cycle or a failed recipe line. |
