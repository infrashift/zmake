---
id: "01a1d3a9-a48c-7f0f-b693-1e63b2b8ea08"
title: "ADR-0021: CI runs every gate on Linux and the unit tests on macOS"
type: "ADR"
tags:
  - "adr"
  - "ci"
  - "platforms"
created: "2026-11-13T00:47:52-06:00"
timestamp: "2026-11-13T00:47:52-06:00"
description: "A GitHub Actions workflow runs make check on Linux and the unit tests plus a fifo jobserver smoke test on macOS arm64 and x86_64, with pinned download checksums."
---

# ADR-0021: CI runs every gate on Linux and the unit tests on macOS

**Status:** Accepted
**Date:** 2026-11-13
**Source:** User request after Phase 19, [ADR-0020](/decisions/adr-0020-a-named-fifo-shares-the-jobserver-off-linux--01a1d399e000.md)

## Context
The gates ran only on one Linux workstation. zmake builds for macOS since Phase 19, but no test ran there. The acceptance suite compares the output of zmake with GNU Make 4.3. macOS has GNU Make 3.81, so the comparisons do not hold there.

## Decision
- `.github/workflows/ci.yml` runs on each push to `main`, on each pull request and on demand.
- The Linux job (`ubuntu-24.04`, GNU Make 4.3) runs `make check`: all gates, also the cross builds.
- The macOS jobs (`macos-latest` on arm64, `macos-15-intel` on x86_64) run `make test` and a smoke test. The smoke test reads the zmake `ZMakefile` with `-n`. It runs four jobs with `-j4` through the default fifo jobserver. It also checks that a recursive zmake joins the fifo pool and that the fifo goes away.
- The jobs download Zig 0.17.1 from ziglang.org and okfw from the `infrashift/okf-wiki` releases. Each download has a pinned SHA-256 sum in the workflow.
- The two unit tests of the pipe jobserver skip off Linux. A test checks there that the pipe style gives `Unsupported` and that the fifo style is the default.

## Consequences
- A change that breaks macOS fails CI before a merge.
- A new Zig or okfw version needs a new pinned sum in the workflow.
- FreeBSD still has only the cross build. GitHub has no FreeBSD runner.

## Alternatives considered
- **Run the acceptance suite on macOS with GNU Make 4.4 from Homebrew.** Rejected for now: some messages of GNU Make 4.4 differ from 4.3, and the suite compares bytes.
- **A third-party action to install Zig.** Rejected: a pinned download with a sum check needs no new dependency.

**Update:** CI also runs the acceptance suite on macOS against GNU Make 4.3 built from source ([ADR-0023](/decisions/adr-0023-the-acceptance-suite-runs-on-macos-against-gnu-make-4-3--01a1d4ecd992.md)).

**Update:** CI also runs the unit tests and the acceptance suite in a FreeBSD VM ([ADR-0024](/decisions/adr-0024-ci-runs-the-tests-in-a-freebsd-vm--01a1d4ff5f9a.md)).
