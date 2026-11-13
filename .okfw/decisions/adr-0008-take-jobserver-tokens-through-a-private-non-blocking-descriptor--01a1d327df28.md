---
id: "01a1d327-df28-7204-adfc-f5e035306456"
title: "ADR-0008: Take jobserver tokens through a private non-blocking descriptor"
type: "ADR"
tags:
  - "adr"
  - "jobserver"
  - "parallel"
created: "2026-11-12T22:26:08-06:00"
timestamp: "2026-11-12T22:26:08-06:00"
description: "zmake reopens the jobserver pipe through /proc with O_NONBLOCK, so it never blocks and never changes the pipe that child makes share."
---

# ADR-0008: Take jobserver tokens through a private non-blocking descriptor

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Phase 5, [Jobserver protocol](/specs/jobserver-protocol--01a1d30ae66b.md)

## Context
A jobserver client must take a token without blocking. The scheduler waits for job completions at the same time. Child makes share the pipe descriptors. `O_NONBLOCK` applies to the open file description, which zmake and its children share. GNU Make children expect a blocking pipe. A `poll` followed by a `read` has a race: another process can take the token between the two calls.

## Decision
- zmake opens `/proc/self/fd/R` again with `O_NONBLOCK`. The new descriptor has its own open file description. zmake reads tokens from it without blocking. The children keep the original blocking descriptor.
- For the GNU Make 4.4 form `fifo:PATH`, zmake opens the fifo with `O_RDWR` and `O_NONBLOCK`.
- When no token is free, the scheduler waits for a job of its own to complete. The first job always runs on the implicit token, so zmake cannot deadlock.
- The executor keeps one token per running job after the first. It returns each token when a job ends, and all tokens before exit.
- zmake passes the pipe ends to each recipe line through `inherit_files`. The child gets them without `FD_CLOEXEC`.
- When the parent did not pass the descriptors in `MAKEFLAGS`, zmake prints the GNU warning and uses `-j1`.

## Consequences
- The design needs `/proc`, so it works on Linux only ([ADR-0002](/decisions/adr-0002-zig-0-17-1-standard-library-only-linux-first--01a1d30ae676.md)).
- A token that a sub-make returns while zmake waits becomes usable after the next completion of a zmake job. Throughput can drop a little. Correctness does not change.

## Alternatives considered
- **`O_NONBLOCK` on the shared descriptor.** Rejected: it breaks GNU Make children.
- **A reader thread that blocks on the pipe.** Rejected: more threads and a harder shutdown, for no gain.

**Update (Phase 19):** this design stays the Linux default. Off Linux, a new pool is a named fifo, and a client cannot share a pipe pool ([ADR-0020](/decisions/adr-0020-a-named-fifo-shares-the-jobserver-off-linux--01a1d399e000.md)).
