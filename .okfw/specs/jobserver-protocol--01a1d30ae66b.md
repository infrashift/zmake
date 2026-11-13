---
id: "01a1d30a-e66b-73b1-a941-d1b04b5d16c5"
title: "Jobserver protocol"
type: "Spec"
tags:
  - "spec"
  - "jobserver"
  - "parallel"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "The GNU Make compatible token protocol that zmake serves and joins for parallel jobs."
---

# Jobserver protocol

**Status:** Draft. [ISSUE-005](/issues/issue-005-parallel-executor-and-gnu-make-jobserver--01a1d30ae6a7.md) implements it in `src/jobserver.zig`.

## Tokens
Each zmake process holds one implicit token. A job needs a token before it starts. The process returns the token to the pool when the job ends.

## Server
With `-jN` and N > 1, and no jobserver in `MAKEFLAGS`, zmake creates the pool:
1. Create a pipe.
2. Write N − 1 token bytes (`+`) into the pipe.
3. Pass both ends of the pipe to each child process.
4. Set `MAKEFLAGS` to `-jN --jobserver-auth=R,W` in the child environment.

## Client
When `MAKEFLAGS` contains `--jobserver-auth=R,W` or `--jobserver-fds=R,W`, zmake joins the parent pool. It also accepts `--jobserver-auth=fifo:PATH`, the GNU Make 4.4 form. A client reads one byte to take a token. It writes the same byte back to return it.

## Descriptors
zmake takes tokens through a private non-blocking descriptor ([ADR-0008](/decisions/adr-0008-take-jobserver-tokens-through-a-private-non-blocking-descriptor--01a1d327df28.md)). When the parent did not pass the descriptors in `MAKEFLAGS`, zmake prints this GNU warning and uses `-j1`:

`zmake: warning: jobserver unavailable: using -j1.  Add '+' to parent make rule.`

## Failure
zmake returns every token that it holds before it exits, also after a failed recipe line.
