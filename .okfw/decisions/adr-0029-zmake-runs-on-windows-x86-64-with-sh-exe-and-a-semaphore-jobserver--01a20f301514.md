---
x-okfw-id: "01a20f30-1514-7eee-9336-51520e3c9a14"
title: "ADR-0029: zmake runs on Windows x86_64 with sh.exe and a semaphore jobserver"
type: "ADR"
tags:
  - "adr"
  - "platforms"
  - "windows"
  - "jobserver"
x-okfw-created: "2026-11-24T14:12:19-06:00"
x-okfw-timestamp: "2026-11-24T14:12:19-06:00"
description: "On Windows x86_64, recipes run in sh.exe from PATH, file names follow the DOS rules, and a new jobserver pool is a named semaphore as in GNU Make for Windows."
---

# ADR-0029: zmake runs on Windows x86_64 with sh.exe and a semaphore jobserver

**Status:** Accepted
**Date:** 2026-11-24
**Source:** Phase 27, [ISSUE-027](/issues/issue-027-windows-x86-64--01a20f300352.md), [ADR-0002](/decisions/adr-0002-zig-0-17-1-standard-library-only-linux-first--01a1d30ae676.md), [ADR-0020](/decisions/adr-0020-a-named-fifo-shares-the-jobserver-off-linux--01a1d399e000.md)

## Context
[ADR-0002](/decisions/adr-0002-zig-0-17-1-standard-library-only-linux-first--01a1d30ae676.md) puts Linux first. zmake also runs on macOS and FreeBSD. zmake did not compile for Windows: the jobserver uses POSIX calls, and `std.posix` stops the build for a Windows target. A cross-compile with the jobserver removed showed that the other modules compile for Windows. The other problems occur at run time:

- No `/bin/sh` is on Windows, so each recipe line fails.
- `abspath`, `realpath` and the working directory assert that a path starts with `/`. A path such as `C:\src` stops zmake.
- `dir`, `notdir`, `$(@D)`, `$(@F)` and the directory part of a pattern rule know only `/`.
- The `:` of a drive name, as in `C:/out/a.o: a.c`, reads as a rule separator.
- NTFS ignores case, as the default macOS file system does.
- `$(MAKE)` holds `C:\...\zmake.exe`. A shell reads each `\` as an escape.

## Decision
- zmake supports Windows on x86_64. `src/path.zig` holds the file name rules. On Windows, `\` also separates the parts of a name. `X:/` or `X:\` starts an absolute name, as in the `HAVE_DOS_PATHS` build of GNU Make. Each function takes a `dos` argument, so the unit tests check the Windows rules on each system.
- The parser skips the `:` of a drive name: one letter at the start of a word, then `:`, then `/` or `\`.
- `VPATH` and `vpath` split directories on `;` on Windows, because a drive name holds a `:`.
- The recipe shell is `sh.exe` when the makefile does not set `SHELL`. Windows finds it through `PATH`, for example the `sh.exe` of Git for Windows or MSYS2. zmake ignores `SHELL` from the environment, as on POSIX systems. zmake has no `cmd.exe` mode.
- zmake gives the shell names with `/`: `$(MAKE)`, `$(abspath)`, `$(realpath)` and the working directory.
- A new pool on Windows is a named semaphore `gmake_semaphore_PID`, as in GNU Make for Windows. `--jobserver-auth` gives the name to a child. `--jobserver-style=sem` selects it. A client opens the semaphore by name. A pipe or fifo pool of a parent cannot reach a Windows process, so zmake warns and uses `-j1`. kernel32 gives the semaphore calls. It is a part of Windows, so this is no new dependency.
- The exact-case check of [ADR-0023](/decisions/adr-0023-the-acceptance-suite-runs-on-macos-against-gnu-make-4-3--01a1d4ecd992.md) also runs on Windows.
- `make cross` builds for `x86_64-windows`. `make dist` adds a `windows-amd64` zip archive with `bin/zmake.exe`.
- CI runs the unit tests on a Windows runner, and a smoke test of the semaphore jobserver and the DOS file names.

## Consequences
- zmake runs on Windows from Git Bash or MSYS2, or from any shell that has `sh.exe` on `PATH`.
- The acceptance suite does not run on Windows. It compares output with GNU Make 4.3 and uses POSIX tools. A follow-up can add it.
- A makefile for `cmd.exe` recipes does not work. Such a makefile must set `SHELL` to a POSIX shell, or use GNU Make.
- Windows on arm64 is not in the scope. The code has no x86_64 assumption, but CI does not test it.

## Alternatives considered
- **A `cmd.exe` mode when no `sh.exe` is on `PATH`, as in GNU Make.** Rejected for now: `cmd.exe` has other quote rules and no `-c`, so each recipe needs a second code path.
- **No jobserver on Windows: `-jN` runs local jobs only.** Rejected: a recursive make then runs N jobs for each level. The semaphore is a small change and matches GNU Make.
- **Use `\` in the names that zmake gives the shell.** Rejected: the POSIX shells of Windows read `\` as an escape.
