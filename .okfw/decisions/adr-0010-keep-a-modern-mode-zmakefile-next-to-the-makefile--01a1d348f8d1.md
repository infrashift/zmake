---
id: "01a1d348-f8d1-73da-98e7-e9bddf071a18"
title: "ADR-0010: Keep a modern-mode ZMakefile next to the Makefile"
type: "ADR"
tags:
  - "adr"
  - "modern-mode"
  - "dogfood"
created: "2026-11-12T23:02:17-06:00"
timestamp: "2026-11-12T23:02:17-06:00"
description: "The repo keeps a Makefile for GNU Make and a ZMakefile for zmake with the same targets; the acceptance suite compares their dry runs."
---

# ADR-0010: Keep a modern-mode ZMakefile next to the Makefile

**Status:** Accepted
**Date:** 2026-11-12
**Source:** User request, Phase 7

## Context
The zmake repo has a GNU Make `Makefile`. zmake runs it in legacy mode. The repo did not use modern mode for its own gates. Users read the repo as an example. GNU Make cannot read a `ZMakefile` with space-indented recipes, so the `Makefile` must stay.

## Decision
- The repo keeps both files with the same targets. `Makefile` is for GNU Make. `ZMakefile` is for zmake, in modern mode.
- The `ZMakefile` declares each target as a task with `@name:`. It has no `.PHONY` list. Its recipes use four spaces.
- zmake finds the `ZMakefile` before the `Makefile`. `zmake check` runs the modern file. `zmake -f Makefile check` runs the legacy file.
- Scenario 8 of `tests/acceptance.sh` takes the goals from the `.PHONY` line of the `Makefile`. For each goal, it compares `zmake -f ZMakefile -n` with GNU Make on the `Makefile`. A difference fails the gate.
- Scenario 7 reads the `Makefile` with `-f Makefile`. Without `-f`, discovery picks the `ZMakefile`, and scenario 7 stops testing legacy mode.

## Consequences
- A new target needs an entry in `.PHONY`, a rule in the `Makefile` and a task in the `ZMakefile`. The acceptance gate reports a missing task.
- The repo runs its own gates through modern mode on each `zmake check`.

## Alternatives considered
- **Replace the `Makefile` with the `ZMakefile`.** Rejected: contributors without zmake need GNU Make.
- **Generate one file from the other.** Rejected: a generator is a new tool. The acceptance comparison gives the same guarantee.
