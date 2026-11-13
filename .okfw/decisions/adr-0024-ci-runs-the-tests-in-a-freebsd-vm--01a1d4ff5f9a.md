---
id: "01a1d4ff-5f9a-7bec-84a9-a159066ad500"
title: "ADR-0024: CI runs the tests in a FreeBSD VM"
type: "ADR"
tags:
  - "adr"
  - "ci"
  - "platforms"
  - "freebsd"
created: "2026-11-13T07:01:08-06:00"
timestamp: "2026-11-13T07:01:08-06:00"
description: "A CI job boots a FreeBSD 15.1 VM with vmactions/freebsd-vm pinned to a commit and runs the unit tests and the acceptance suite against GNU Make 4.3 there."
---

# ADR-0024: CI runs the tests in a FreeBSD VM

**Status:** Accepted
**Date:** 2026-11-13
**Source:** [ISSUE-022](/issues/issue-022-test-runs-on-freebsd--01a1d4ee3b4d.md), [ADR-0021](/decisions/adr-0021-ci-runs-every-gate-on-linux-and-the-unit-tests-on-macos--01a1d3a9a48c.md)

## Context
zmake builds for FreeBSD since Phase 19, but no test ran there. FreeBSD has no `/proc` by default, its own `/bin/sh` and its own libc. The jobserver code has FreeBSD paths. GitHub has no FreeBSD runner.

## Decision
- A CI job on a Linux runner boots a FreeBSD 15.1 VM with the `vmactions/freebsd-vm` action. The action copies the checkout into the VM.
- The workflow pins the action to the commit of its `v1.5.9` tag, `c46abacb49f09938ca4e1702d15d836285d694cc`. A tag can move, and a commit cannot.
- In the VM, the job installs `bash` and `curl` with `pkg`. It downloads Zig 0.17.1 for x86_64 FreeBSD from ziglang.org and checks a pinned SHA-256 sum.
- The job builds GNU Make 4.3 from the GNU release, as on macOS ([ADR-0023](/decisions/adr-0023-the-acceptance-suite-runs-on-macos-against-gnu-make-4-3--01a1d4ecd992.md)). `build.sh` of GNU Make needs no make program.
- FreeBSD has clang as `cc` and no `gcc`. The job links `gcc` to `cc`, as macOS does, because scenario 3 of `PLAN.md` uses `CC := gcc`.
- The job runs `make test` and `make acceptance` as root, the user of the VM.

## Consequences
- CI compares zmake with GNU Make 4.3 on Linux, macOS and FreeBSD.
- The VM boots in QEMU. The job takes about five minutes, as the macOS jobs do.
- The action is a third-party dependency of CI, not of zmake. A new version of the action needs a review and a new pinned commit.

## Alternatives considered
- **Only the cross build.** Rejected: a cross build does not run the code.
- **`cross-platform-actions/action`.** Rejected for now: it also boots a QEMU VM, and `vmactions/freebsd-vm` lists the current FreeBSD releases.
- **A self-hosted FreeBSD runner.** Rejected: it needs a machine and its upkeep.
