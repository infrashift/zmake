---
id: "01a1d36e-9f70-754a-88d9-5649bb50d84a"
title: "ADR-0013: Include files share the source stack and are not remade"
type: "ADR"
tags:
  - "adr"
  - "reader"
  - "include"
created: "2026-11-12T23:43:24-06:00"
timestamp: "2026-11-12T23:43:24-06:00"
description: "include reads each file as a source on the reader stack with per-file messages; a missing file is reported after reading, and zmake does not remake included files."
---

# ADR-0013: Include files share the source stack and are not remade

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Phase 11, [ISSUE-011](/issues/issue-011-include-and-makefile-list--01a1d34ecd30.md)

## Context
`include FILES` reads other input files at the point of the directive. Large projects split their Makefiles this way. GNU Make also remakes an included file when a rule can make it, and then reads all input again from the start. Messages must name the file of each statement.

## Decision
- The reader reads each included file into a new source on the source stack of [ADR-0012](/decisions/adr-0012-a-reader-evaluates-each-statement-while-it-reads--01a1d36899c8.md). Include files and eval texts share the limit of 64 open sources. A file that includes itself stops at the limit.
- Each source has a file name. When the top source changes, the reader points the parser and the evaluator at its file. Each rule and each graph node keeps the file of its rule, so recipe errors, override warnings and cycle messages name the right file.
- Each file must close its own conditionals.
- `MAKEFILE_LIST` gets the name of each input file when zmake starts to read it.
- `-include` and `sinclude` skip a missing file. For `include`, zmake records the first missing file and reports it after it reads all input, as GNU Make does: `file:line: name: No such file or directory`, then `No rule to make target`.
- zmake does not remake included files. When a rule can make the missing file, zmake stops with `zmake does not remake included files; make 'name' first`. It does not fail in silence.
- A name with `*`, `?` or `[` is a glob, as in GNU Make. It gives the matching files in sorted order, or the name itself when nothing matches.
- zmake does not search include directories. A name is a path relative to the working directory.

## Consequences
- Acceptance scenario 12 matches GNU Make 4.3 for the output, the recipe error and three error messages.
- A project that generates its dependency files with a rule and includes them needs a first build step that makes the files, or `-include`.

## Alternatives considered
- **Remake included files and restart.** Rejected for now: a restart reads all input again and needs the executor before the graph exists. The clear error covers the case.
- **Search `-I` directories and `/usr/include`.** Deferred: few Makefiles depend on it.
