---
id: "01a1d34e-cd51-7b49-9174-40eac5382897"
title: "ISSUE-016: Built-in variables, implicit rules and suffix rules"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-16"
  - "rules"
  - "closed"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-13T00:13:33-06:00"
description: "Phase 16: the GNU Make built-in variables and implicit rules, old-style suffix rules, and -r / -R."
---

# ISSUE-016: Built-in variables, implicit rules and suffix rules

**Status/Phase:** Closed · Phase 16

## Description
GNU Make defines `CC`, `CFLAGS` and many implicit rules. Many Makefiles depend on them.

## Acceptance Criteria
- [x] Built-in variables such as `CC`, `CXX`, `AR`, `RM`, `COMPILE.c` and `LINK.o`, with the `default` origin.
- [x] The common built-in implicit rules for C, C++, assembler and linking, with a lower priority than the rules of the input file.
- [x] Old-style suffix rules (`.c.o:`, `.c:`) with `.SUFFIXES`.
- [x] `-r` disables the built-in rules. `-R` also disables the built-in variables.
- [x] `make check` passes.

## Resolution
Done on 2026-11-13 in Phase 16. `make check` passes: 96 unit tests, 93 acceptance checks.

- `src/builtin_rules.zig` holds the built-in variables, rules and suffixes of GNU Make 4.3. A script generated it from `make -p` ([ADR-0018](/decisions/adr-0018-built-in-rules-come-from-gnu-make-and-follow-the-suffix-list--01a1d38a371f.md)).
- Suffix rules become pattern rules when `.SUFFIXES` has their suffixes. Built-in rules come after the rules of the input file. A file rule replaces or cancels a built-in rule.
- `-r`, `-R` and `MAKEFLAGS += -r` work. The `r` and `R` letters pass to sub-makes.
- The pattern search has two passes, and match-anything rules have the limits of GNU Make.
- Acceptance scenario 17 matches GNU Make 4.3 in ten cases. A C program builds with only `all: tool` in the input file.

## Related
[PLAN.md](../../PLAN.md)
