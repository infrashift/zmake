---
title: Design Decisions
description: A summary of the zmake architecture decision records (ADRs) in the project wiki.
---

The project wiki in `.okfw/decisions/` holds the full ADRs. Each ADR records the
context, the decision, the consequences and the rejected options. This page
gives a summary of each.

### ADR-0001: Adopt an OKF wiki for project knowledge

An OKF wiki in `.okfw/` holds the architecture, the specs, the decisions and
the issues. The `okfw` CLI manages it. `PLAN.md` stays the phase checklist, and
each phase has a mirror issue in the wiki.

### ADR-0002: Zig 0.17.1, standard library only, Linux first

`build.zig.zon` pins Zig 0.17.1. zmake uses the Zig standard library only and
does not link libc. The jobserver calls `pipe2` and `fcntl` directly, so zmake
supports Linux first.

### ADR-0003: Adapt the NASA Power of 10 rules to Zig

The NASA/JPL rules for safety-critical code apply to zmake:

- No recursion. The evaluator and the graph use explicit stacks.
- Fixed loop bounds. A loop that reaches its limit returns an error.
- Functions of 60 lines or fewer, with two or more assertions each on average.
- One arena per run, capped by hard limits.

`scripts/nasa-lint.py` checks the rules that a script can check. Release
builds are `ReleaseSafe`, so the assertions stay active.

### ADR-0004: Modern mode declares tasks and infers phony targets

Modern mode adds `@name:` and `task name:`. It infers a phony target for a bare
name whose recipe does not refer to `$@`. The inference uses the name and the
recipe, not the state of the disk. A phony target that shadows a path runs and
prints a warning. Legacy mode does not change. See
[Tasks and Phony Inference](../../guides/tasks-and-phony-inference/).

### ADR-0005: Unsupported directives fail loudly

The parser rejects `include`, the conditionals, `define`, `export`, `override`
and `vpath` with `file:line`. The evaluator rejects functions outside its
four. A parser that does not know these lines misreads them, and the build
then does the wrong thing with no error.

### ADR-0006: Expansion uses an explicit frame stack

Make expansion nests, and Power of 10 forbids recursion. `Evaluator.expand`
keeps an explicit stack of at most 64 frames. Each frame expands one string. A
second frame for the same recursive variable gives the GNU error
`Recursive variable 'X' references itself (eventually)`.

### ADR-0007: Delete partial targets by mode

GNU Make deletes a partial file target after a failed recipe line only with
`.DELETE_ON_ERROR`. Legacy mode follows GNU Make. Modern mode deletes the
target by default, and keeps `.PRECIOUS` and `.SECONDARY` targets.

### ADR-0008: Take jobserver tokens through a private non-blocking descriptor

zmake opens `/proc/self/fd/R` again with `O_NONBLOCK`. It takes tokens from
that descriptor without blocking. The children keep the original blocking
descriptor. When no token is free, zmake waits for one of its own jobs. The
first job always runs on the implicit token, so zmake cannot deadlock. See
[Parallel Builds and the Jobserver](../../guides/parallel-builds/).

### ADR-0009: Document zmake with Astro Starlight on GitHub Pages

This site is an Astro Starlight site in `docs/`. GitHub Actions builds it with
bun and deploys it to GitHub Pages. The docs toolchain is not part of the Zig
build, so ADR-0002 does not change.

### ADR-0010: Keep a modern-mode ZMakefile next to the Makefile

The repo keeps a `Makefile` for GNU Make and a `ZMakefile` for zmake, with the
same targets. The `ZMakefile` uses `@name:` tasks and space-indented recipes.
The acceptance suite compares the dry runs of both files for each target. See
[Make Targets](../../reference/make-targets/).

### ADR-0011: Lazy functions use staged calls on the frame stack

`if`, `and`, `or` and `intcmp` expand only the arguments that they need.
`foreach`, `let` and `call` bind their variables in a scope and expand the body
in a child frame. The scope restores the shadowed variables after the body. No
function calls the evaluator again, so a recursive `$(call ...)` needs no
recursion in zmake. See [Functions](../../reference/functions/).

### ADR-0012: A reader evaluates each statement while it reads

The reader reads the input file line by line and applies each statement at
once, so a conditional sees the variables above it. Explicit stacks hold the
open conditionals and the open sources. `$(eval ...)` queues its text, and the
reader reads the text after the statement. An eval therefore takes effect one
statement later than in GNU Make, and a recipe cannot call `eval`. See
[Conditionals and define](../../guides/conditionals/).

### ADR-0013: Include files share the source stack and are not remade

`include` reads each file into a new source on the stack of ADR-0012. Each rule
keeps the name of its file for messages. A missing file stops zmake after it
reads all input, as in GNU Make. zmake does not remake an included file. When a
rule can make the file, zmake says so and stops. See
[Include Files](../../guides/include/).

### ADR-0014: Export flags decide the recipe environment

The evaluator keeps an export flag for each name and a switch for `export`
with no names. For each job, the executor starts from the environment of zmake,
adds each exported variable expanded for the target, and removes each
`unexport` name. Command-line variables and changed environment variables go
by default, as in GNU Make. See [Export and the Environment](../../guides/export/).

### ADR-0015: Directory search keeps the found path per node

A graph node keeps the path where `vpath` or `VPATH` found its file. The
automatic variables give the found paths. A target that is out of date gets its
own name back and rebuilds in the working directory, as in GNU Make. See
[Directory Search](../../guides/vpath/).

### ADR-0016: Target contexts are layers that a pre-pass builds

Each graph node gets the variable layers of the node that first needs it,
without the `private` variables, plus one layer of its own assignments. A pass
over the graph from the goals down builds the layers before the first job. The
evaluator reads the layers before the global variables. The same phase made a
serial build run in the depth-first order of GNU Make. See
[Target-Specific Variables](../../guides/target-variables/).

### ADR-0017: A double-colon target keeps one instance per rule

The graph node of a `::` target keeps each rule as an instance with its own
prerequisites and recipe. The executor decides each instance on its own and
runs the due ones in file order, in one job. Since this phase, zmake prints the
"is up to date" message of a goal when the goal is done, as GNU Make does.

### ADR-0018: Built-in rules come from GNU Make and follow the suffix list

A script generates the built-in variables and rules from `make -p` of GNU Make
4.3. The rules come after the rules of the input file and need their suffixes
in `.SUFFIXES`. The pattern search tries rules without a chain first. A rule
with the target `%` alone does not make a file of a specific type. See
[Pattern Rules](../../guides/pattern-rules/#built-in-rules).

### ADR-0019: Letter flags share one table for options and MAKEFLAGS

One table maps the letters `B`, `k`, `n`, `q`, `r`, `R`, `s` and `t` to their
flags, for the command line and for `MAKEFLAGS`. Under `-k`, a failed node fails
the nodes that need it, and the other nodes go on. Under `-q`, zmake runs
nothing and exits with 1 when a goal is out of date. Under `-t`, it sets the
time of each out-of-date file. See [CLI](../../reference/cli/).

### ADR-0020: A named fifo shares the jobserver off Linux

On Linux, a new jobserver stays a pipe. On macOS and the BSDs, it is a named
fifo, as in GNU Make 4.4. Each process can open a fifo with its own
non-blocking descriptor. `--jobserver-style` selects the style. A client off
Linux cannot share a pipe pool and uses `-j1`. `make cross` builds for macOS and
FreeBSD. See [Parallel Builds](../../guides/parallel-builds/#pipe-and-fifo).

### ADR-0021: CI runs every gate on Linux and the unit tests on macOS

A GitHub Actions workflow runs `make check` on Linux. On macOS (arm64 and
x86_64), it runs the unit tests and a smoke test of the fifo jobserver. The
acceptance suite compares bytes with GNU Make 4.3, which macOS does not have.
Each download of Zig and okfw has a pinned SHA-256 sum.
