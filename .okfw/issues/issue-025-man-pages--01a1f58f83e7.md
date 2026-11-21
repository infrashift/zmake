---
id: "01a1f58f-83e7-7d3e-a1dc-b455402942e9"
title: "ISSUE-025: Man pages"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-25"
  - "docs"
  - "man"
  - "closed"
created: "2026-11-19T14:46:25-06:00"
timestamp: "2026-11-19T14:46:31-06:00"
description: "zmake ships zmake(1) and zmakefile(5), and zig build -p ~/.local installs them where man finds them on Linux, macOS and FreeBSD."
---

# ISSUE-025: Man pages

# ISSUE-025: Man pages

**Status/Phase:** Closed · Phase 25

## Description
zmake had no man page. Users install the binary in `~/.local/bin` and expect `man zmake` to work with no setup on Linux, macOS and FreeBSD. See [ADR-0027](/decisions/adr-0027-man-pages-are-mdoc-files-installed-under-the-prefix--01a1f58f63a3.md).

## Acceptance Criteria
- [x] `man/zmake.1` documents each option, the input file discovery, the environment and the exit status.
- [x] `man/zmakefile.5` documents the two modes, tasks, target kinds and recipe indentation.
- [x] `zig build -p PREFIX` installs the pages in `PREFIX/share/man/man1` and `PREFIX/share/man/man5`.
- [x] `make lint` and `zmake lint` check the macros. A bad macro fails the task. The dry runs of both files are the same.
- [x] `scripts/ste-check.py` checks the text of the pages.
- [x] Acceptance scenario 23: each option of `zmake --help` is in `zmake(1)`, and `man -w` finds both pages through `PATH`.
- [x] The docs site has a Manual Pages page. Getting Started, the README and the CLI page tell users to install with `-p ~/.local`.
- [x] `make check` and `zmake check` pass.

## Resolution
Done on 2026-11-19 in Phase 25 ([ADR-0027](/decisions/adr-0027-man-pages-are-mdoc-files-installed-under-the-prefix--01a1f58f63a3.md)).

- `build.zig` installs `man/zmake.1` and `man/zmakefile.5` next to `bin/zmake`.
- On Linux, `PATH=$tmp/bin:$PATH man -w zmake` with no `MANPATH` gives `$tmp/share/man/man1/zmake.1`. The macOS and FreeBSD CI jobs run the same check in scenario 23.
- The lint task fails on a probe page with an unknown macro.
- The drift check of scenario 23 fails when `man/zmake.1` has no `--modern` entry.
