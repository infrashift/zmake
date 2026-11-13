---
id: "01a1d38a-371f-7551-8663-c702ef6ff35b"
title: "ADR-0018: Built-in rules come from GNU Make and follow the suffix list"
type: "ADR"
tags:
  - "adr"
  - "database"
  - "builtins"
created: "2026-11-13T00:13:33-06:00"
timestamp: "2026-11-13T00:13:33-06:00"
description: "Generated built-in variables and rules from GNU Make 4.3; rules follow .SUFFIXES and come after file rules; a two-pass pattern search and match-anything limits as in GNU Make."
---

# ADR-0018: Built-in rules come from GNU Make and follow the suffix list

**Status:** Accepted
**Date:** 2026-11-13
**Source:** Phase 16, [ISSUE-016](/issues/issue-016-built-in-variables-implicit-rules-and-suffix-rules--01a1d34ecd51.md)

## Context
Many Makefiles depend on the built-in variables of GNU Make, such as `CC` and `COMPILE.c`, and on its built-in rules, such as `%.o: %.c`. Without them, `$(CC)` expands to nothing and `app: main.o` has no rule. Old Makefiles also use suffix rules such as `.c.o:`. In GNU Make, most built-in rules are suffix rules, so `.SUFFIXES:` with no names turns them off.

## Decision
- `src/builtin_rules.zig` holds 58 variables, 48 rules and the default suffix list. A script generated the file from `make -p -f /dev/null` of GNU Make 4.3, so the text is the same. The RCS, SCCS and archive member rules stay out.
- The built-in variables have the `default` origin. `-R` leaves them out and implies `-r`.
- `Builder.finish` keeps the suffix list (`.SUFFIXES` adds names, or clears the list with none). It turns `.c.o:` into `%.o: %.c` and `.c:` into `%: %.c` when the final list has the suffixes. Another dot name stays a file target. An unknown special target stays an error.
- Then it adds each built-in rule after the rules of the input file, when the list has both suffixes. A pattern rule of the input file with the same target and prerequisite replaces the built-in rule. Without a recipe, it cancels it. `-r` and `MAKEFLAGS += -r` in the input file add no built-in rule.
- The pattern search has two passes, as in GNU Make. The first pass takes only rules whose prerequisites exist or have rules. The second pass allows a chain. So `all: hello` uses `%: %.c`, not `%: %.o` through `hello.o`.
- A match-anything rule (target `%`) does not apply to a name with a known suffix or a more specific pattern target. It also does not apply to the prerequisite of another pattern rule. Without this limit, each source file costs dozens of file checks.
- A recipe error of a built-in rule shows `[<builtin>: main.o]`, as in GNU Make.
- `cli.Flags` holds the flags that pass through `MAKEFLAGS` as letters: `n`, `r` and `R`.

## Consequences
- Acceptance scenario 17 matches GNU Make 4.3 in ten cases. They cover the built-in compile and link lines, user rules, cancel rules, `-r`, `-R` and `MAKEFLAGS += -r`. They also cover suffix rules, `.SUFFIXES:`, origins and the error format.
- A C program builds with an input file that has only `all: tool`.
- The unit tests of the graph use `database.load`, which adds no built-in rules, so they keep their small rule sets.

## Alternatives considered
- **No built-in rules in modern mode.** Rejected: modern mode keeps Makefile snippets working with no change, and `-r` turns the rules off.
- **Write the tables by hand.** Rejected: 48 recipes with exact spaces are easy to copy wrong. The generator reads them from GNU Make.
