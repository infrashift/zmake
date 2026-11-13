---
id: "01a1d390-363b-7edb-9bfe-4ca59157649f"
title: "ADR-0019: Letter flags share one table for options and MAKEFLAGS"
type: "ADR"
tags:
  - "adr"
  - "cli"
  - "executor"
created: "2026-11-13T00:20:06-06:00"
timestamp: "2026-11-13T00:20:06-06:00"
description: "One table maps B k n q r R s t for options and MAKEFLAGS; -k fails dependents and goes on, -q exits 1 when out of date, -t sets file times."
---

# ADR-0019: Letter flags share one table for options and MAKEFLAGS

**Status:** Accepted
**Date:** 2026-11-13
**Source:** Phase 17, [ISSUE-017](/issues/issue-017-the-options-k-q-t-and-b--01a1d34ecd58.md)

## Context
GNU Make users expect `-k` (keep going), `-q` (question), `-t` (touch), `-B` (always make) and `-s` (silent), and short option clusters such as `-kj4`. A sub-make gets the flags through the first word of `MAKEFLAGS`, for example `Bks`.

## Decision
- `cli.Flags` holds the letter flags `B`, `k`, `n`, `q`, `r`, `R`, `s` and `t`, in the order that GNU Make writes them to `MAKEFLAGS`. The same table reads the letters back from `MAKEFLAGS`.
- A short argument is a cluster. Each letter sets a flag. `f`, `C` and `j` take the rest of the word, or the next argument. The long forms (`--keep-going`, `--question`, `--touch`, `--always-make`, `--silent`, `--quiet`) also work.
- `-k`: a failed job marks its node as failed and completes it. A node with a failed prerequisite fails without a recipe. The other nodes go on. A goal that failed prints `Target 'x' not remade because of errors.`. The exit code is 2.
- `-q`: an out-of-date node runs nothing and sets a flag. zmake prints no goal messages. The exit code is 1 when a goal is out of date, else 0. `main.zig` has a second error, `Outdated`, for exit code 1.
- `-t`: an out-of-date file target gets the current time through `Dir.setTimestampsNow`, or zmake creates the file. zmake prints `touch NAME`. A phony target gets nothing.
- `-B`: each prerequisite counts as newer, so each target is out of date.
- `-s`: no recipe line echoes.

## Consequences
- Acceptance scenario 18 matches GNU Make 4.3 in twelve cases, also the exit codes and the `MAKEFLAGS` letters.
- Under `-t` and `-q`, zmake does not run lines with `+` or `$(MAKE)`. GNU Make runs them. The docs state the difference.

## Alternatives considered
- **Run `touch` through the shell for `-t`.** Rejected: a file name with spaces needs quotes, and the standard library sets the time directly.
