---
id: "01a1f58f-63a3-758e-9624-9817f65f4046"
title: "ADR-0027: Man pages are mdoc files installed under the prefix"
type: "ADR"
tags:
  - "adr"
  - "docs"
  - "man"
  - "install"
created: "2026-11-19T14:46:17-06:00"
timestamp: "2026-11-19T14:46:17-06:00"
description: "zmake(1) and zmakefile(5) are hand-written mdoc files in man/ that zig build installs in PREFIX/share/man, so a ~/.local prefix needs no MANPATH change."
---

# ADR-0027: Man pages are mdoc files installed under the prefix

# ADR-0027: Man pages are mdoc files installed under the prefix

**Status:** Accepted
**Date:** 2026-11-19
**Source:** User request: add man pages, and install them on macOS and Linux next to a binary in `~/.local/bin`.

## Context
zmake had no man page. The CLI reference was only on the docs site ([ADR-0009](/decisions/adr-0009-document-zmake-with-astro-starlight-on-github-pages--01a1d33eea33.md)). The docs tell users to put the binary in `~/.local/bin`. That directory is not a system directory, so the man pages need a location that `man` finds with no setup.

When `MANPATH` is not set, `man` makes its search path from `PATH` on the three supported systems:

- **Linux, man-db.** `manpath(5)`: for each `PATH` entry with no `MANPATH_MAP` line, man-db adds `../man`, `man`, `../share/man` and `share/man` when they exist.
- **macOS.** `manpath(1)`: for a `PATH` entry that ends in `/bin`, `man` adds `../share/man` and `../man`. `path_helper` sets `MANPATH` only when it is already set.
- **FreeBSD.** `manpath(1)`: the same rule as macOS.

`zig build -p PREFIX` writes the binary to `PREFIX/bin`. So the pages in `PREFIX/share/man` are next to the binary. On this Linux host, `PATH=$tmp/bin:$PATH man -w zmake` with no `MANPATH` gives `$tmp/share/man/man1/zmake.1`.

## Decision
- `man/zmake.1` documents the command line. `man/zmakefile.5` documents the input file in the two modes. Both use the mdoc macros. No tool generates them.
- `build.zig` installs them in `share/man/man1` and `share/man/man5` under the install prefix, next to `bin/zmake`.
- The docs recommend `zig build --release -p ~/.local`. For all users, they recommend `-p /usr/local`.
- `make lint` and `zmake lint` check the macros with `mandoc -T lint -W warning`, or with `groff -mandoc -ww -z` when mandoc is not on the `PATH`. Any message fails the task. This follows the fallback pattern of [ADR-0026](/decisions/adr-0026-semscope-checks-the-power-of-10-rules--01a1ec7f697a.md). The Makefile and the ZMakefile change together ([ADR-0010](/decisions/adr-0010-keep-a-modern-mode-zmakefile-next-to-the-makefile--01a1d348f8d1.md)).
- `scripts/ste-check.py` checks the text of the pages against ASD-STE100.
- Acceptance scenario 23 checks that each option of `zmake --help` has an entry in `zmake(1)`. It also checks that `man -w` finds both pages through `PATH`, on Linux, macOS and FreeBSD.

## Consequences
- A change to an option or to the modern syntax changes a man page in the same commit.
- A user who sets `MANPATH` adds `~/.local/share/man`, or starts or ends the value with a colon. The [Manual Pages](https://infrashift.github.io/zmake/docs/reference/man-pages/) page tells how.
- The Linux CI runner needs groff or mandoc for `make lint`. The Ubuntu image has groff.
- `apropos zmake` finds the pages only after `mandb` or `makewhatis`. `man zmake` does not need them.

## Alternatives considered
- **Generate the pages from Markdown with pandoc or scdoc.** Rejected: a new tool, and ADR-0002 keeps the dependencies to a minimum. mdoc is the native format of macOS and FreeBSD.
- **A `make install` target.** Rejected: `zig build -p` installs the binary and the pages in one command on all three systems. A second way to install adds a target to both Makefiles.
- **Put the page in the binary (`zmake --man`).** Rejected: `man zmake` is the command that users expect.
- **Tell users to set `MANPATH` in the shell profile.** Rejected: a set `MANPATH` turns off the search from `PATH` and hides other man pages.
