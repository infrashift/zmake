---
id: "01a1d376-370d-7d6c-b5cf-eeea7576bdbc"
title: "ADR-0015: Directory search keeps the found path per node"
type: "ADR"
tags:
  - "adr"
  - "dag"
  - "vpath"
created: "2026-11-12T23:51:42-06:00"
timestamp: "2026-11-12T23:51:42-06:00"
description: "vpath and VPATH search for missing files; each graph node keeps the found path for automatic variables, and an out-of-date target rebuilds under its own name."
---

# ADR-0015: Directory search keeps the found path per node

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Phase 13, [ISSUE-013](/issues/issue-013-vpath-and-vpath--01a1d34ecd3c.md)

## Context
`VPATH` and `vpath` tell GNU Make where to look for a file that is not in the working directory. The found path goes into `$<` and `$^`. A target that directory search finds keeps the found path when it is up to date. When it is out of date, GNU Make rebuilds it in the working directory, under its own name.

## Decision
- The database keeps the `vpath` directives in file order and the directories of `VPATH`. Directory lists split on colons and white space. `vpath PATTERN` removes the entries of PATTERN, and `vpath` alone removes all entries.
- `dag.locate` looks for a name in the working directory first. Then it tries the `vpath` entries whose pattern matches, in file order, then the `VPATH` directories. An absolute name and a phony target are never searched.
- A graph node keeps the found path. `known`, and so the viability of pattern rules, uses the same search.
- The executor keeps the path of each node on disk. An out-of-date file node with a found path gets its own name back before the recipe runs. So the rebuild happens in the working directory.
- The automatic variables `$<`, `$^`, `$+` and `$?` give the paths, not the names. `$@` is always the name.
- `GPATH` is not supported.

## Consequences
- Acceptance scenario 14 runs one probe of eight cases through GNU Make 4.3 and zmake. The output is the same.
- Each missing file costs one `access` call per search directory.

## Alternatives considered
- **Search only prerequisites without a rule.** Rejected: GNU Make also searches targets, and a library that is up to date in `lib/` must not rebuild.
