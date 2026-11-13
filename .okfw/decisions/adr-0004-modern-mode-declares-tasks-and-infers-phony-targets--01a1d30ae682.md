---
id: "01a1d30a-e682-705b-bb8c-e82edab78880"
title: "ADR-0004: Modern mode declares tasks and infers phony targets"
type: "ADR"
tags:
  - "adr"
  - "syntax"
  - "phony"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "Modern mode removes .PHONY boilerplate with @name/task syntax and a bare-name heuristic, and runs a shadowed task with a warning."
---

# ADR-0004: Modern mode declares tasks and infers phony targets

**Status:** Accepted
**Date:** 2026-11-12
**Source:** `PLAN.md` sections 1 and 4

## Context
In GNU Make, a target without `.PHONY` is a file. A `build:` rule does nothing when a `build/` directory exists. Each project repeats the `.PHONY` list. Users forget entries, and the failure is silent.

## Decision
- Legacy mode keeps GNU semantics with no change.
- Modern mode adds `@name:` and `task name:` to declare a task.
- Modern mode infers `inferred_phony` for a bare name whose recipe does not refer to `$@`.
- An `inferred_phony` target runs even when a path with the same name exists. zmake prints a warning that names the `@` fix.
- Modern mode still honors `.PHONY`, so Makefile snippets work with no change.

The [Syntax modes and target kinds](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md) spec defines the rules.

## Consequences
- A file target with a bare name, for example `app`, needs `$@` in its recipe. Without `$@`, it becomes `inferred_phony` and always runs.
- The `$@` scan reads the unexpanded recipe. A recipe that hides `$@` in a variable gives `inferred_phony`.

## Alternatives considered
- **Keep `.PHONY` only.** Rejected: it keeps the silent failure.
- **Infer phony when no file exists.** Rejected: the result changes with the state of the disk.
