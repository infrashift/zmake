---
id: "01a1d372-90f3-71a2-a315-0a79c51d672a"
title: "ADR-0014: Export flags decide the recipe environment"
type: "ADR"
tags:
  - "adr"
  - "executor"
  - "environment"
created: "2026-11-12T23:47:43-06:00"
timestamp: "2026-11-12T23:47:43-06:00"
description: "An export flag per name and an export-all switch decide, with the origin, which variables each job gets; the executor builds the environment per job."
---

# ADR-0014: Export flags decide the recipe environment

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Phase 12, [ISSUE-012](/issues/issue-012-export-and-unexport--01a1d34ecd36.md)

## Context
Recipes read variables from their environment. GNU Make decides for each variable whether a recipe gets it. The rules have several layers: `export` and `unexport`, the origin of the variable, and `export` with no names. Until Phase 12, each recipe got the environment of zmake with no change, plus `MAKEFLAGS` and `MAKELEVEL`.

## Decision
- The evaluator keeps an export flag per name (`export NAME` true, `unexport NAME` false) and an `export_all` switch (`export` alone and `.EXPORT_ALL_VARIABLES` on, `unexport` alone off).
- `Evaluator.exported` decides for one variable, in this order:
  1. A flag decides.
  2. `SHELL`, `MAKEFLAGS`, `MAKELEVEL` and `MAKEFILE_LIST` stay as zmake manages them.
  3. A built-in variable (origin `default`) never goes. A command-line variable always goes.
  4. A name that the environment of zmake has goes, also with a value that the input file changed.
  5. With `export_all`, a file variable goes when its name is a valid shell name.
- The executor builds the environment of each job. It starts from the base environment and adds each exported variable, expanded with the automatic variables of the target. Then it removes each `unexport` name. When no flag, no `export_all`, no command-line variable and no changed environment variable exists, all jobs share the base environment.
- `export NAME = value` takes every assignment operator, `export define`, `export override` and `override export`.
- `$(shell ...)` keeps the environment of zmake, as in GNU Make 4.3.

## Consequences
- Acceptance scenario 13 compares the recipe environment with GNU Make 4.3 in four cases. All match.
- An exported recursive variable expands once for each job, as in GNU Make. A `$(shell ...)` in its value runs for each job.

## Alternatives considered
- **Expand the exports once, before the first job.** Rejected: `export T = $@` must give each target its own value.
- **Export every file variable.** Rejected: GNU Make does not, and large environments slow down each command.
