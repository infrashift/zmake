---
id: "01a1d30a-e687-7d24-9b97-623f1ab16cd4"
title: "ADR-0005: Unsupported directives fail loudly"
type: "ADR"
tags:
  - "adr"
  - "parser"
  - "compatibility"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "The parser rejects include, conditionals, define, export and vpath with a file:line error instead of a silent misparse."
---

# ADR-0005: Unsupported directives fail loudly

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Implementation plan

## Context
The plan does not cover `include`, `-include`, `ifeq`, `ifneq`, `ifdef`, `ifndef`, `else`, `endif`, `define`, `endef`, `export`, `unexport`, `override` or `vpath`. A parser that does not know these lines reads them as rules or assignments. The build then does the wrong thing with no error.

## Decision
The parser rejects each directive from the list with this error. Since Phase 10, the reader handles the conditionals, `define`, `override` and `undefine` ([ADR-0012](/decisions/adr-0012-a-reader-evaluates-each-statement-while-it-reads--01a1d36899c8.md)). `load` stays out of scope. A directive word followed by `=` or `:` is a variable or a target name, not a directive.

`Makefile:7: *** unsupported directive 'ifeq'.  Stop.`

The evaluator also rejects GNU functions that it does not implement. Without this check, such a reference expands to an empty variable. Since Phase 9, only `eval` and `guile` remain ([ADR-0011](/decisions/adr-0011-lazy-functions-use-staged-calls-on-the-frame-stack--01a1d35f6009.md)).

The parser also rejects three forms outside the scope: double-colon rules (`a:: b`), target-specific variables (`a: CC = x`) and shell assignments (`X != cmd`).

## Consequences
- A real-world Makefile with conditionals fails at once, with a clear message.
- Each directive is a follow-up issue when a user needs it.

## Alternatives considered
- **Ignore unknown directives.** Rejected: a silent misparse is worse than an error.
