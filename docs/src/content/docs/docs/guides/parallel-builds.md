---
title: Parallel Builds and the Jobserver
description: Run jobs in parallel with -jN, and share one pool of jobs with GNU Make through the jobserver.
---

`-jN` runs up to N jobs at the same time. zmake serves and joins the GNU Make
jobserver. A recursive `$(MAKE)` and a parent GNU Make share one pool of jobs.

```sh
zmake -j8
zmake -j 8 test
```

## Failed jobs

A failed recipe line stops the build. With `-j`, zmake prints this message and
waits for the running jobs:

```text
zmake: *** Waiting for unfinished jobs....
```

`.NOTPARALLEL` in the input file makes zmake run one job at a time.

## Tokens

Each zmake process holds one implicit token. A job needs a token before it
starts. The process returns the token to the pool when the job ends. zmake
returns every token before it exits, also after a failed recipe line.

## zmake as the server

zmake creates the pool when the command line gives `-jN` with N > 1 and
`MAKEFLAGS` has no jobserver:

1. zmake creates a pipe.
2. zmake writes N − 1 token bytes (`+`) into the pipe.
3. zmake passes both ends of the pipe to each child process.
4. The child environment gets `MAKEFLAGS` with `-jN --jobserver-auth=R,W`.

## zmake as a client

zmake joins the pool of its parent when `MAKEFLAGS` contains one of these forms:

| Form | Source |
|---|---|
| `--jobserver-auth=R,W` | GNU Make 4.2 and later, zmake |
| `--jobserver-fds=R,W` | GNU Make 4.1 and earlier |
| `--jobserver-auth=fifo:PATH` | GNU Make 4.4 and later |

A client reads one byte to take a token. It writes the same byte back to
return it.

## Recursive builds

A recipe line that contains `$(MAKE)` gets the jobserver descriptors:

```make
.PHONY: all
all:
	$(MAKE) -C lib
	$(MAKE) -C app
```

A line with `+` or with `$(MAKE)` also runs under `-n`. The sub-make gets `n`
in `MAKEFLAGS`, so it prints its recipe lines and does not run them.

When the parent did not pass the descriptors, zmake prints the GNU warning and
uses `-j1`:

```text
zmake: warning: jobserver unavailable: using -j1.  Add '+' to parent make rule.
```

## Design

zmake takes tokens through a private non-blocking descriptor. It opens
`/proc/self/fd/R` again with `O_NONBLOCK`. The children keep the original
blocking descriptor, which GNU Make children expect. This design needs `/proc`,
so the jobserver works on Linux only. See
[ADR-0008](../../project/decisions/#adr-0008-take-jobserver-tokens-through-a-private-non-blocking-descriptor).
