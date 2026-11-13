---
id: "01a1d30a-e676-7686-be81-d87471a0c77f"
title: "ADR-0002: Zig 0.17.1, standard library only, Linux first"
type: "ADR"
tags:
  - "adr"
  - "toolchain"
  - "zig"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "zmake targets Zig 0.17.1 with no dependencies outside the standard library, and supports Linux first."
---

# ADR-0002: Zig 0.17.1, standard library only, Linux first

# ADR-0002: Zig 0.17.1, standard library only, Linux first

**Status:** Accepted
**Date:** 2026-11-12
**Source:** `PLAN.md` section 1, user decision during planning

## Context
The original plan named Zig `0.13.0` and `0.14.0-dev`. Later releases replaced the reader and writer APIs and moved I/O behind the `std.Io` interface. The machine had no Zig toolchain. The latest stable release on 2026-11-12 is 0.17.1.

## Decision
- Pin Zig 0.17.1 as `minimum_zig_version` in `build.zig.zon`. Install the toolchain from ziglang.org into `~/.local/zig/` and verify the SHA-256 sum.
- Use the standard library only. `main` receives `std.process.Init` and passes its `io` to each module that does I/O.
- Support Linux first. The jobserver calls `pipe2` and `fcntl` through `std.posix.system`, because 0.17 removed most `std.posix` wrappers.

## Consequences
- Each Zig upgrade can break the std API. The pinned version keeps the build reproducible.
- macOS and BSD support need a review of the jobserver system calls.

## Alternatives considered
- **Zig 0.13.0 as written.** Rejected: three releases old, with an I/O API that later releases removed.
- **Link libc for the jobserver.** Rejected: a static binary without libc is simpler to ship.
