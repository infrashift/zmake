---
id: "01a1d4ec-d992-723d-aa03-46050d1ba081"
title: "ADR-0023: The acceptance suite runs on macOS against GNU Make 4.3"
type: "ADR"
tags:
  - "adr"
  - "ci"
  - "platforms"
  - "macos"
created: "2026-11-13T06:40:54-06:00"
timestamp: "2026-11-13T06:40:54-06:00"
description: "The macOS CI jobs build GNU Make 4.3 from source and run the acceptance suite; on macOS zmake checks the exact case of file names through directory listings, as GNU Make does."
---

# ADR-0023: The acceptance suite runs on macOS against GNU Make 4.3

**Status:** Accepted
**Date:** 2026-11-13
**Source:** [ISSUE-021](/issues/issue-021-acceptance-suite-on-macos--01a1d4dbc5ce.md), [ADR-0021](/decisions/adr-0021-ci-runs-every-gate-on-linux-and-the-unit-tests-on-macos--01a1d3a9a48c.md)

## Context
CI ran only the unit tests on macOS. The acceptance suite compares the output of zmake with GNU Make 4.3, and macOS has GNU Make 3.81. GNU Make 4.4 from Homebrew has some different messages, so a comparison with 4.4 does not hold.

The first run of the suite on macOS found a bug. The default macOS file system ignores case, so `access("makefile")` finds `Makefile`. zmake then used the name `makefile` in its messages, and a built-in rule found `util.C` for `util.c`. GNU Make looks each name up in a cached listing of its directory, with exact case, so it sees neither name.

## Decision
- The macOS jobs build GNU Make 4.3 from the GNU release, with a pinned SHA-256 sum. The jobs put it first in `PATH` as `make` and run `make acceptance`.
- The acceptance script uses only commands that work on Linux, macOS and FreeBSD. BSD `date` has no `%N`, so `$EPOCHREALTIME` of bash 5 gives the time. macOS runs the script with bash 3.2, so Python gives the time there. `paste` gets `-` as its file.
- Off Linux, the script expects the documented `-j1` warning in a GNU Make pipe pool ([ADR-0020](/decisions/adr-0020-a-named-fifo-shares-the-jobserver-off-linux--01a1d399e000.md)). On Linux, it checks that zmake shares the pool.
- On macOS, zmake checks the exact case of a name after `access` finds it. `src/dircache.zig` reads each directory listing once and keeps it for the graph search. The search for the input file and the existence and `vpath` checks of the graph use it.
- Other systems compare case already, so they skip the check.
- `$(wildcard)`, `include` and the time checks keep `access`, `open` and `stat`, because GNU Make also uses these calls there.

## Consequences
- CI compares zmake with GNU Make 4.3 on Linux, on macOS arm64 and on macOS x86_64.
- On macOS, the graph search reads each directory that it checks once.
- The unit test of the input file search compares the exact name again. Commit 320d2bc accepted `makefile`, on the wrong assumption that GNU Make does the same.

## Alternatives considered
- **GNU Make 4.4 from Homebrew.** Rejected: the suite compares bytes, and some 4.4 messages differ from 4.3.
- **A case-insensitive comparison in the tests.** Rejected: it hides a real difference from GNU Make.
