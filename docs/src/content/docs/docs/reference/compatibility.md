---
title: Compatibility
description: The GNU Make features that zmake supports, and the features that stop the build with an error.
---

zmake supports a defined subset of GNU Make. It stops with an error for each
feature outside this subset. A silent misparse is worse than an error
([ADR-0005](../../project/decisions/#adr-0005-unsupported-directives-fail-loudly)).

## Supported

| Area | Features |
|---|---|
| Assignments | `=`, `:=`, `::=`, `?=`, `+=`, command-line overrides |
| Rules | Explicit rules, pattern rules, order-only prerequisites, inline `; recipe` text |
| Automatic variables | `$@`, `$<`, `$^`, `$+`, `$*`, `$?` and their `D` and `F` forms |
| Functions | All GNU Make functions except `eval` and `guile` ([Functions](../functions/)), substitution references |
| Variables | `MAKE`, `MAKEFLAGS`, `MAKELEVEL`, `SHELL` |
| Recipe prefixes | `@`, `-`, `+` |
| Options | `-f`, `-C`, `-j`, `-n` |
| Jobserver | `--jobserver-auth=R,W`, `--jobserver-fds=R,W`, `--jobserver-auth=fifo:PATH` |

## Special targets

| Target | Effect |
|---|---|
| `.PHONY` | Each prerequisite is a phony target. |
| `.DEFAULT_GOAL` | The first prerequisite is the default goal. `.DEFAULT_GOAL := x` also works. |
| `.PRECIOUS`, `.SECONDARY` | zmake keeps these targets after a failed recipe line. |
| `.SILENT` | zmake does not echo the recipe lines of the prerequisites, or of all targets when the list is empty. |
| `.NOTPARALLEL` | zmake runs one job at a time. |
| `.DELETE_ON_ERROR` | Legacy mode deletes a partial file target after a failed recipe line. |
| `.SUFFIXES`, `.INTERMEDIATE`, `.NOTINTERMEDIATE`, `.POSIX`, `.LOW_RESOLUTION_TIME` | No effect. zmake accepts them. |

Any other special target is an error. An old-style suffix rule such as `.c.o:`
is an error.

## Not supported

These features stop the build with `file:line`:

| Feature | Error |
|---|---|
| `include`, `-include` | `unsupported directive` |
| `ifeq`, `ifneq`, `ifdef`, `ifndef`, `else`, `endif` | `unsupported directive` |
| `define`, `endef` | `unsupported directive` |
| `export`, `unexport`, `override`, `vpath` | `unsupported directive` |
| `$(eval ...)` and `$(guile ...)` | `unsupported function` |
| Double-colon rules (`a:: b`) | Parse error |
| Target-specific variables (`a: CC = x`) | Parse error |
| Shell assignments (`X != cmd`) | Parse error |

A directive word followed by `=` or `:` is a variable or a target name, not a
directive.

## Known differences

- **Built-in variables and rules.** zmake has no built-in implicit rules and no built-in variables such as `CC`. An undefined variable expands to an empty string.
- **Cycles.** A circular dependency is an error. GNU Make drops the edge with a warning.
- **Modern-mode deletion.** Modern mode deletes a partial file target by default. See [Syntax Modes](../../guides/syntax-modes/).
- **Recursive variable errors.** The error shows the line that uses the variable. GNU Make shows the line that defines it.
- **Intermediate files.** GNU Make deletes a file that a chain of pattern rules made. zmake keeps it.
- **Platforms.** zmake supports Linux. The jobserver needs `/proc`.

## Hard limits

zmake caps its memory and its work
([ADR-0003](../../project/decisions/#adr-0003-adapt-the-nasa-power-of-10-rules-to-zig)).
An input that exceeds a limit fails with a clear error.

| Limit | Value |
|---|---|
| Input file size | 16 MiB |
| Expansion depth | 64 frames |
| Output of one expansion | 4 MiB |
| Prerequisite depth | 1024 |
| Graph nodes | 65536 |

See the [Roadmap](../../project/roadmap/) for the planned features.
