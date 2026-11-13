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
| Built-ins | The built-in variables and implicit rules of GNU Make 4.3, suffix rules, `.SUFFIXES` |
| Rules | Explicit rules, pattern rules, static pattern rules, double-colon rules, order-only prerequisites, inline `; recipe` text |
| Target variables | Target-specific and pattern-specific variables, `override`, `export`, `private` ([Target-Specific Variables](../../guides/target-variables/)) |
| Automatic variables | `$@`, `$<`, `$^`, `$+`, `$*`, `$?` and their `D` and `F` forms, `$\|` |
| Functions | All GNU Make functions except `guile` ([Functions](../functions/)), substitution references |
| Directives | `ifeq`, `ifneq`, `ifdef`, `ifndef`, `else`, `endif`, `define`, `override`, `undefine` ([Conditionals](../../guides/conditionals/)), `include`, `-include`, `sinclude` ([Include Files](../../guides/include/)), `export`, `unexport` ([Export](../../guides/export/)), `vpath` ([Directory Search](../../guides/vpath/)) |
| Variables | `MAKE`, `MAKEFLAGS`, `MAKELEVEL`, `SHELL`, `MAKEFILE_LIST`, `VPATH` |
| Recipe prefixes | `@`, `-`, `+` |
| Options | `-f`, `-C`, `-j`, `-n`, `-r`, `-R`, `-k`, `-q`, `-t`, `-B`, `-s`, and clusters such as `-kj4` |
| Jobserver | `--jobserver-auth=R,W`, `--jobserver-fds=R,W`, `--jobserver-auth=fifo:PATH` |

## Special targets

| Target | Effect |
|---|---|
| `.PHONY` | Each prerequisite is a phony target. |
| `.DEFAULT_GOAL` | The first prerequisite is the default goal. `.DEFAULT_GOAL := x` also works. |
| `.PRECIOUS`, `.SECONDARY` | zmake keeps these targets after a failed recipe line. |
| `.SILENT` | zmake does not echo the recipe lines of the prerequisites, or of all targets when the list is empty. |
| `.NOTPARALLEL` | zmake runs one job at a time. |
| `.EXPORT_ALL_VARIABLES` | Each variable with a valid shell name goes to the recipe environment. |
| `.DELETE_ON_ERROR` | Legacy mode deletes a partial file target after a failed recipe line. |
| `.SUFFIXES` | Sets the suffixes of suffix rules and built-in rules. With no names, it clears the list. |
| `.INTERMEDIATE`, `.NOTINTERMEDIATE`, `.POSIX`, `.LOW_RESOLUTION_TIME` | No effect. zmake accepts them. |

Any other special target is an error.

## Not supported

These features stop the build with `file:line`:

| Feature | Error |
|---|---|
| `load` | `unsupported directive` |
| `$(guile ...)` | `unsupported function` |
| `$(eval ...)` in a recipe | `$(eval ...) in a recipe is not supported` |
| Double-colon pattern rules (`%.o:: %.c`) | `double-colon pattern rules are not supported` |
| Shell assignments (`X != cmd`) | Parse error |

A directive word followed by `=` or `:` is a variable or a target name, not a
directive.

## Known differences

- **Cycles.** A circular dependency is an error. GNU Make drops the edge with a warning.
- **Modern-mode deletion.** Modern mode deletes a partial file target by default. See [Syntax Modes](../../guides/syntax-modes/).
- **Recursive variable errors.** The error shows the line that uses the variable. GNU Make shows the line that defines it.
- **Eval timing.** An eval takes effect after the statement that calls it, not inside the same expansion ([ADR-0012](../../project/decisions/#adr-0012-a-reader-evaluates-each-statement-while-it-reads)).
- **Include files.** zmake does not remake an included file, and it does not search include directories ([Include Files](../../guides/include/)).
- **GPATH.** zmake does not support `GPATH`.
- **Static pattern variables.** `objs: %.o: NAME = value` stops with `invalid target-specific variable`. GNU Make reads `NAME` as a prerequisite.
- **`-q` and `-t`.** zmake does not run recipe lines with `+` or `$(MAKE)` under `-q` and `-t`. GNU Make runs them.
- **Intermediate files.** GNU Make deletes a file that a chain of pattern rules made. zmake keeps it.
- **Platforms.** zmake builds for Linux, macOS and FreeBSD. CI runs all tests on Linux and the unit tests on macOS. On macOS and FreeBSD, zmake cannot join a pipe jobserver of a parent and uses `-j1`.

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
