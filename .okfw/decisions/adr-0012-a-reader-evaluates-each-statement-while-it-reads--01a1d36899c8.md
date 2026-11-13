---
id: "01a1d368-99c8-740e-b7f1-21f85e1c0159"
title: "ADR-0012: A reader evaluates each statement while it reads"
type: "ADR"
tags:
  - "adr"
  - "reader"
  - "conditionals"
created: "2026-11-12T23:36:50-06:00"
timestamp: "2026-11-12T23:36:50-06:00"
description: "A line-by-line reader applies each statement at once for conditionals and define, and reads queued eval texts as sources on an explicit stack instead of recursing."
---

# ADR-0012: A reader evaluates each statement while it reads

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Phase 10, [ISSUE-010](/issues/issue-010-conditionals-define-override-undefine-and-eval--01a1d34ecd29.md)

## Context
Until Phase 9, the parser read the whole input file into statements, and `database.load` replayed them. A conditional needs the variables that the lines above it define, so the test cannot wait for a later pass. `$(eval text)` adds input text while zmake reads. GNU Make applies an eval at once, inside the expansion that calls it. That is recursion: expand, read, expand. Rule R1 forbids it.

## Decision
- `src/reader.zig` reads the input file line by line. It feeds each line to the parser and gives each new statement to the `database.Builder` at once.
- The reader handles `ifeq`, `ifneq`, `ifdef`, `ifndef`, `else` (also `else ifeq ...`) and `endif` before the parser sees the line. An explicit stack holds the open conditionals, with a limit of 256. A conditional line does not end an open rule, so a conditional inside a recipe selects recipe lines.
- In a skipped branch, the reader looks only at conditionals and at `define` blocks. Other lines can have any syntax there.
- `define NAME [op]` reads raw lines up to the matching `endef`. Nested `define` blocks count. The body keeps tabs and `#`.
- `override` gives an assignment the `override` origin, above the command line. `undefine` removes a variable unless a higher origin defines it.
- `$(eval text)` adds the text to a queue and expands to nothing. After the statement, the reader reads each queued text as a new source on an explicit stack (limit 64). A line that waits for an open rule to close holds its place until the eval texts are read.
- A line with no separator, such as `$(RULE)`, is an expression. A non-empty expansion goes into the same queue, so it can define a rule, as in GNU Make.
- A recipe cannot call `eval`. The reader is done at that time. zmake stops with `$(eval ...) in a recipe is not supported`.
- The executor splits each expanded recipe line at newlines that no backslash escapes. Each part is a command with its own prefixes, so a canned recipe from `define` runs line by line, as in GNU Make.
- `parser.parse` stays for the unit tests. It still rejects the directives, because it cannot evaluate them.

## Consequences
- The output of the probes in acceptance scenario 11 matches GNU Make 4.3, also the error messages.
- Difference: an eval takes effect after the statement that calls it. `X := $(eval Y := 1)$(Y)` gives an empty `X` in zmake and `1` in GNU Make. The common forms, `$(eval $(call TEMPLATE,...))` on its own line and `$(foreach ...,$(eval ...))`, give the same result.
- `include`, `export` and `vpath` come in Phases 11 to 13 and use the same source stack.

## Alternatives considered
- **Apply an eval inside the expansion.** Rejected: recursion through `expand` and the reader.
- **Evaluate the conditionals in a second pass over the statements.** Rejected: a conditional must see the variables above it, and an eval can add conditionals.
