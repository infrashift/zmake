---
id: "01a1d399-e000-758d-8036-97af04d1d46c"
title: "ADR-0020: A named fifo shares the jobserver off Linux"
type: "ADR"
tags:
  - "adr"
  - "jobserver"
  - "platforms"
created: "2026-11-13T00:30:39-06:00"
timestamp: "2026-11-13T00:30:39-06:00"
description: "On macOS and the BSDs a new jobserver is a named fifo, as in GNU Make 4.4; Linux keeps the pipe; a client off Linux cannot share a pipe pool and uses -j1."
---

# ADR-0020: A named fifo shares the jobserver off Linux

**Status:** Accepted
**Date:** 2026-11-13
**Source:** Phase 19, [ISSUE-019](/issues/issue-019-jobserver-on-macos-and-the-bsds--01a1d34ecd67.md), [ADR-0008](/decisions/adr-0008-take-jobserver-tokens-through-a-private-non-blocking-descriptor--01a1d327df28.md)

## Context
The jobserver of [ADR-0008](/decisions/adr-0008-take-jobserver-tokens-through-a-private-non-blocking-descriptor--01a1d327df28.md) needs two Linux features: `pipe2` and a new open of `/proc/self/fd/R`. macOS has no `pipe2`, so zmake did not compile for macOS. FreeBSD compiled, but `-j` failed at run time without `/proc`. Without `/proc`, no portable call gives a private non-blocking descriptor for a pipe. A `poll` before a `read` has a race, and the race can block the scheduler while it holds tokens.

GNU Make 4.4 uses a named fifo by default (`--jobserver-auth=fifo:PATH`). Each process opens the path and gets its own open file description, so `O_NONBLOCK` stays private on each POSIX system. GNU Make 4.3 stops with a fatal error when it sees a fifo.

## Decision
- On Linux, a new pool stays a pipe, so GNU Make 4.3 children keep working.
- On macOS and the BSDs, a new pool is a named fifo in `$TMPDIR` (else `/tmp`), mode 0600, named `zmake-jobserver-PID`. zmake opens it read-write and non-blocking, writes the tokens, and deletes it at the end. This is the default of GNU Make 4.4.
- `--jobserver-style=fifo|pipe` selects the style, as in GNU Make 4.4. `pipe` on a system other than Linux stops with an error. The acceptance tests use `fifo` on Linux to test the portable path.
- A client joins a fifo pool on each system. On a system other than Linux, or when `/proc` is missing, a client cannot share a pipe pool. zmake then warns and uses `-j1`. A wrong token count is worse than a slower build.
- `mknodat` makes the fifo on Linux. Elsewhere, `mkfifo` of the C library makes it. Zig links the C library on each system except Linux, so this is no new dependency.
- `make cross` builds zmake for macOS and FreeBSD on arm64 and x86_64. `make check` runs it.

## Consequences
- zmake builds for macOS and FreeBSD. The unit tests and the acceptance tests run on Linux only. Acceptance scenario 20 runs the fifo server and a recursive zmake on the fifo pool on Linux.
- Under the make 3.81 of macOS, which uses a pipe, zmake runs its own jobs one at a time.
- A crash leaves the fifo in `$TMPDIR`, as with GNU Make.

## Alternatives considered
- **`poll` and then `read` on the shared pipe.** Rejected: another process can take the token between the two calls, and the scheduler then blocks.
- **A thread that blocks on `read` and hands tokens over.** Rejected: the thread cannot stop at the end, and a token that it reads after the last job is lost to the parent.
- **`O_NONBLOCK` on the shared pipe for one `read`.** Rejected: a child that reads at the same time gets `EAGAIN`, and old makes treat it as a fatal error.

**Update:** CI runs the unit tests and a fifo jobserver smoke test on macOS ([ADR-0021](/decisions/adr-0021-ci-runs-every-gate-on-linux-and-the-unit-tests-on-macos--01a1d3a9a48c.md)).
