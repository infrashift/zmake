---
id: "01a1d30a-e6a7-7338-a296-8216af8a4d8c"
title: "ISSUE-005: Parallel executor and GNU Make jobserver"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-5"
  - "executor"
  - "jobserver"
  - "closed"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T22:26:33-06:00"
description: "Phase 5: out-of-date checks, recipe execution, -j scheduling, the jobserver, and the acceptance scenarios."
---

# ISSUE-005: Parallel executor and GNU Make jobserver

**Status/Phase:** Closed · Phase 5

## Description
Build `src/executor.zig` and `src/jobserver.zig`. Add `tests/acceptance.sh`.

## Acceptance Criteria
- [x] File targets rebuild when they are missing or older than a prerequisite. Phony targets always run.
- [x] Each recipe line runs in its own `/bin/sh -c`. The prefixes `@`, `-` and `+` work. `-n` prints only.
- [x] A failed recipe line gives exit code 2. zmake deletes a partial file target by the rules of [ADR-0007](/decisions/adr-0007-delete-partial-targets-by-mode--01a1d327df21.md).
- [x] `-jN` runs up to N jobs. The [Jobserver protocol](/specs/jobserver-protocol--01a1d30ae66b.md) works as server and as client.
- [x] Acceptance: the `build/` directory scenario passes in modern mode.
- [x] Acceptance: `@deploy: build` with 4-space indentation runs `build`, then `deploy`.
- [x] Acceptance: the legacy C project rebuilds only dirty objects and respects `.PHONY`.
- [x] `make check` passes.

## Resolution
Done on 2026-11-12. `make check` passes: 74 unit tests, 42 acceptance checks, 159 functions and 318 assertions. `zmake check` also passes on the zmake repo itself.

- **Canonical scenarios:** all three pass in `tests/acceptance.sh`. The dry runs of the legacy C project match GNU Make 4.3 byte for byte.
- **Parallel:** four one-second jobs take 1.0 s with `-j4` and 4.0 s with `-j1`.
- **Jobserver:** a recursive zmake sees `--jobserver-auth`. Under a GNU Make `-j2` parent, four one-second jobs take 2.0 s, so zmake obeys the pool ([ADR-0008](/decisions/adr-0008-take-jobserver-tokens-through-a-private-non-blocking-descriptor--01a1d327df28.md)).
- **Correction to the plan:** GNU Make deletes a failed target only with `.DELETE_ON_ERROR` ([ADR-0007](/decisions/adr-0007-delete-partial-targets-by-mode--01a1d327df21.md)).
- **Bug found by acceptance:** the executor copied a `Diagnostic` onto itself. The Zig safety check `@memcpy arguments alias` stopped it. The fix copies only between distinct buffers.
- **Release mode:** `zig build --release` builds `ReleaseSafe`, so assertions and safety checks stay active.
- **Test isolation:** `tests/acceptance.sh` clears `MAKEFLAGS` and `MAKELEVEL`. A parent make otherwise changes the output of GNU Make.

## Related
[Architecture](/architecture/zmake-architecture-overview--01a1d30ae65a.md) · [PLAN.md](../../PLAN.md)
