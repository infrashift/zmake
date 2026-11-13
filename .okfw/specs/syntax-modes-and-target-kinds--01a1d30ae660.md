---
id: "01a1d30a-e660-720e-b2f1-8da726521244"
title: "Syntax modes and target kinds"
type: "Spec"
tags:
  - "spec"
  - "syntax"
  - "phony"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "How zmake selects legacy or modern mode, which recipe indentation each mode accepts, and how it classifies each target."
---

# Syntax modes and target kinds

**Status:** Draft. [ISSUE-002](/issues/issue-002-context-sensitive-lexer-and-dual-mode-parser--01a1d30ae694.md) and [ISSUE-003](/issues/issue-003-two-phase-variable-evaluator-and-target-classification--01a1d30ae69a.md) implement it. [ADR-0004](/decisions/adr-0004-modern-mode-declares-tasks-and-infers-phony-targets--01a1d30ae682.md) records the design.

## Mode selection
1. Use `--modern` or `--legacy` when the command line gives one.
2. Otherwise, use the basename of the `-f` file: `ZMakefile` or `Make.zig.mk` selects modern mode. Any other name selects legacy mode.
3. Otherwise, search the directory in this order: `ZMakefile`, `Make.zig.mk`, `GNUmakefile`, `makefile`, `Makefile`.

## Recipe lines
- **Legacy mode:** a recipe line starts with a tab. A space-indented line after a rule is an error (`missing separator`).
- **Modern mode:** a recipe line starts with a tab or with two or more spaces. The first indented line sets the indent of the block. zmake strips that indent from each line of the block. A non-blank line at column 0 ends the block. Blank lines and comment lines do not end the block. A recipe line with less indent than the block is an error.
- **Modern mode limit:** inside a recipe block, each line with two or more spaces is a recipe line. Put variable assignments at column 0.

## Task syntax (modern mode only)
- `@name: prerequisites` and `task name: prerequisites` declare a task.
- In a rule with several targets, each target carries `@`, or none does.
- `task:` with no name declares a plain target named `task`.
- In legacy mode, zmake reads `@name` and `task` as ordinary target names.

## Target kinds
| Kind | Meaning |
|---|---|
| `file` | zmake compares modification times. The recipe runs when the target is missing or older than a prerequisite. |
| `explicit_phony` | The recipe always runs. zmake never examines the disk for the target. |
| `inferred_phony` | Modern mode only. The recipe always runs. zmake examines the disk only for the collision warning. |

## Classification
**Legacy mode:**
- A target that `.PHONY` names is `explicit_phony`.
- Any other target is `file`.

**Modern mode:** apply the first rule that matches.
1. **Rule A.** A task, or a target that `.PHONY` names, is `explicit_phony`.
2. **Rule B.** A name with `/` or `.`, a pattern rule, or a recipe that refers to `$@` gives `file`.
3. **Rule C.** Any other target that has a rule is `inferred_phony`.

A name with no rule (a prerequisite only) is always `file`. The `$@` scan reads the unexpanded recipe. It matches `$@`, `$(@)`, `${@}`, `$(@D)`, `$(@F)`, `${@D}` and `${@F}`.

## Special targets
| Target | Effect |
|---|---|
| `.PHONY` | Each prerequisite is `explicit_phony`. |
| `.DEFAULT_GOAL` | The first prerequisite is the default goal. The variable form `.DEFAULT_GOAL := x` also works. |
| `.PRECIOUS`, `.SECONDARY` | zmake keeps these targets after a failed recipe line. |
| `.SILENT` | zmake does not echo the recipe lines of the prerequisites, or of all targets when the list is empty. |
| `.NOTPARALLEL` | zmake runs one job at a time. |
| `.SUFFIXES`, `.DELETE_ON_ERROR`, `.INTERMEDIATE`, `.NOTINTERMEDIATE`, `.POSIX`, `.LOW_RESOLUTION_TIME` | No effect. zmake accepts them. |

Any other special target is an error. An old-style suffix rule such as `.c.o:` is an error.

## Goal resolution
zmake resolves each target in this order:
1. Use the explicit rules for the target. Merge their prerequisites. The last recipe wins, with the GNU warnings.
2. For an explicit rule without a recipe, take the recipe from a pattern rule. Its prerequisites come first, so `$<` is the pattern source.
3. Otherwise, use the viable pattern rule with the shortest stem. The first rule in the file wins a tie.
4. Otherwise, use an existing file or a `.PHONY` name with no recipe.
5. Otherwise, stop with `No rule to make target`.

A pattern prerequisite is viable when it exists, has an explicit rule or is phony. zmake also accepts one level of chaining: a second pattern rule can make it from such files. A pattern without `/` matches the file part of a name, and the directory joins the stem.

**Cycles:** a circular dependency stops zmake with the path and a line for each rule. GNU Make drops the circular edge with a warning and continues. zmake does not continue, because the plan requires an error.

## Collision guard
When an `inferred_phony` target has the same name as a file or directory, zmake runs the recipe. It also prints this warning:

`zmake: warning: target 'test' shadows existing path './test'; prefix with '@test:' to silence`
