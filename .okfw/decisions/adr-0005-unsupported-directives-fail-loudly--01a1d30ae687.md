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

# ADR-0005: Unsupported directives fail loudly

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Implementation plan

## Context
The plan does not cover `include`, `-include`, `ifeq`, `ifneq`, `ifdef`, `ifndef`, `else`, `endif`, `define`, `endef`, `export`, `unexport`, `override` or `vpath`. A parser that does not know these lines reads them as rules or assignments. The build then does the wrong thing with no error.

## Decision
The parser rejects each directive from the list with this error:

`Makefile:7: *** unsupported directive 'ifeq'.  Stop.`

## Consequences
- A real-world Makefile with conditionals fails at once, with a clear message.
- Each directive is a follow-up issue when a user needs it.

## Alternatives considered
- **Ignore unknown directives.** Rejected: a silent misparse is worse than an error.
