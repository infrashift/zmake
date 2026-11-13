---
id: "01a1d34e-cd51-7b49-9174-40eac5382897"
title: "ISSUE-016: Built-in variables, implicit rules and suffix rules"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-16"
  - "rules"
  - "open"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:08:39-06:00"
description: "Phase 16: the GNU Make built-in variables and implicit rules, old-style suffix rules, and -r / -R."
---

# ISSUE-016: Built-in variables, implicit rules and suffix rules

**Status/Phase:** Open · Phase 16

## Description
GNU Make defines `CC`, `CFLAGS` and many implicit rules. Many Makefiles depend on them.

## Acceptance Criteria
- [ ] Built-in variables such as `CC`, `CXX`, `AR`, `RM`, `COMPILE.c` and `LINK.o`, with the `default` origin.
- [ ] The common built-in implicit rules for C, C++, assembler and linking, with a lower priority than the rules of the input file.
- [ ] Old-style suffix rules (`.c.o:`, `.c:`) with `.SUFFIXES`.
- [ ] `-r` disables the built-in rules. `-R` also disables the built-in variables.
- [ ] `make check` passes.

## Related
[PLAN.md](../../PLAN.md)
