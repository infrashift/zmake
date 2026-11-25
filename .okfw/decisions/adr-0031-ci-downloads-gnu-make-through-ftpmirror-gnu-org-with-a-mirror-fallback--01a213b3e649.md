---
x-okfw-id: "01a213b3-e649-7d06-b8a9-31709b09dfb6"
title: "ADR-0031: CI downloads GNU Make through ftpmirror.gnu.org with a mirror fallback"
type: "ADR"
tags:
  - "adr"
  - "ci"
x-okfw-created: "2026-11-25T11:14:46-06:00"
x-okfw-timestamp: "2026-11-25T11:14:46-06:00"
description: "The macOS and FreeBSD CI jobs download the GNU Make 4.3 source through scripts/fetch-gnu-make.sh, which tries ftpmirror.gnu.org, ftp.gnu.org and then large GNU mirrors, and checks the pinned SHA-256."
---

# ADR-0031: CI downloads GNU Make through ftpmirror.gnu.org with a mirror fallback

**Status:** Accepted
**Date:** 2026-11-25
**Source:** User request after [ADR-0030](/decisions/adr-0030-ci-downloads-zig-from-the-community-mirrors-first--01a213272a14.md), [ADR-0023](/decisions/adr-0023-the-acceptance-suite-runs-on-macos-against-gnu-make-4-3--01a1d4ecd992.md), [ADR-0024](/decisions/adr-0024-ci-runs-the-tests-in-a-freebsd-vm--01a1d4ff5f9a.md)

## Context
The macOS jobs and the FreeBSD VM build GNU Make 4.3 from its source archive, because the acceptance suite compares output with GNU Make 4.3. The jobs downloaded the archive from ftp.gnu.org only. On 2026-11-25, ftp.gnu.org did not answer one macOS job for 75 s, and the job failed. GNU asks downloaders to use `ftpmirror.gnu.org`, which sends each request to a near mirror. [ADR-0030](/decisions/adr-0030-ci-downloads-zig-from-the-community-mirrors-first--01a213272a14.md) put a mirror fallback on the Zig download, and listed GNU Make as a follow-up.

## Decision
- `scripts/fetch.sh SHA256 OUT URL...` tries each URL in turn and checks the pinned SHA-256, as in [ADR-0030](/decisions/adr-0030-ci-downloads-zig-from-the-community-mirrors-first--01a213272a14.md). `scripts/fetch-zig.sh` now gives its URLs to `fetch.sh`.
- `fetch.sh` makes two passes over the URLs. The first pass stops a source that sends less than 1 MB/s for 20 s. In the CI of PR #8, a mirror sent Zig at 200 kB/s, and the download took 7 minutes. The second pass runs only if no source is that fast. It accepts 50 kB/s, with a limit of 10 minutes for each file. A slow mirror then costs 20 s, but a slow day does not stop CI.
- `scripts/fetch-gnu-make.sh VERSION SHA256 OUT` gives `fetch.sh` these sources: `ftpmirror.gnu.org`, then `ftp.gnu.org`, then five large GNU mirrors.
- The macOS jobs and the FreeBSD VM call `fetch-gnu-make.sh`. The Linux job uses the GNU Make 4.3 of Ubuntu 24.04 and downloads nothing.

## Consequences
- An outage of ftp.gnu.org does not stop CI.
- The pinned SHA-256 makes each mirror safe.
- A mirror in the list can go away. That costs one failed attempt.

## Alternatives considered
- **Install GNU Make 4.3 from Homebrew or FreeBSD packages.** Rejected: the packages have a newer version, and the acceptance suite needs 4.3 exactly.
- **Keep the GNU Make archive in the repository.** Rejected: it adds a 2 MB archive to the repository.
