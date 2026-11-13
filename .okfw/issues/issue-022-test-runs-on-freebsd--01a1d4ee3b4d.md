---
id: "01a1d4ee-3b4d-78b1-ba99-e5975ae1afd0"
title: "ISSUE-022: Test runs on FreeBSD"
type: "issue"
kind: "issue"
tags:
  - "issue"
  - "follow-up"
  - "ci"
  - "platforms"
  - "closed"
created: "2026-11-13T06:42:24-06:00"
timestamp: "2026-11-13T07:01:08-06:00"
description: "A CI job runs the unit tests and the acceptance suite in a FreeBSD VM, with pinned downloads and a pinned VM action."
---

# ISSUE-022: Test runs on FreeBSD

**Status/Phase:** Closed · Phase 22

## Description
zmake builds for FreeBSD with `make cross`, but no test runs there. GitHub has no FreeBSD runner. The Phase 19 jobserver code has FreeBSD paths without `/proc`, and FreeBSD has its own `/bin/sh` and libc.

## Acceptance Criteria
- [x] A CI job boots a FreeBSD VM and runs `make test` and `make acceptance` there.
- [x] The job installs Zig 0.17.1 for FreeBSD and builds GNU Make 4.3, each with a pinned SHA-256 sum.
- [x] The workflow pins the third-party action that boots the VM to a commit, and an ADR records it.
- [x] `make check` passes on Linux, and CI passes on all jobs.

## Resolution
Done on 2026-11-13 in Phase 22. `make check` passes, and CI passes on Linux, macOS arm64, macOS x86_64 and FreeBSD ([ADR-0024](/decisions/adr-0024-ci-runs-the-tests-in-a-freebsd-vm--01a1d4ff5f9a.md)).

- A CI job boots a FreeBSD 15.1 VM with `vmactions/freebsd-vm`, pinned to the commit of its `v1.5.9` tag.
- The VM gets Zig 0.17.1 for FreeBSD and GNU Make 4.3, each with a pinned SHA-256 sum.
- In the VM, the unit tests give 102 passed and 2 skipped, and the acceptance suite gives 107 passed, 0 failed.
- The first run failed scenario 3 only: FreeBSD has no `gcc`. The job links `gcc` to `cc`, as macOS does.

## Related
[ADR-0021](/decisions/adr-0021-ci-runs-every-gate-on-linux-and-the-unit-tests-on-macos--01a1d3a9a48c.md) · [ADR-0023](/decisions/adr-0023-the-acceptance-suite-runs-on-macos-against-gnu-make-4-3--01a1d4ecd992.md) · [PLAN.md](../../PLAN.md)
