---
x-okfw-id: "01a21327-2a14-74e5-b325-f16f8a1eeb8c"
title: "ADR-0030: CI downloads Zig from the community mirrors first"
type: "ADR"
tags:
  - "adr"
  - "ci"
  - "release"
x-okfw-created: "2026-11-25T08:41:03-06:00"
x-okfw-timestamp: "2026-11-25T08:41:03-06:00"
description: "CI and the release workflow download Zig through scripts/fetch-zig.sh, which tries the Zig community mirrors in a random order and then ziglang.org, and checks the pinned SHA-256."
---

# ADR-0030: CI downloads Zig from the community mirrors first

**Status:** Accepted
**Date:** 2026-11-25
**Source:** User request after release 0.2.0, [ADR-0021](/decisions/adr-0021-ci-runs-every-gate-on-linux-and-the-unit-tests-on-macos--01a1d3a9a48c.md), [ADR-0024](/decisions/adr-0024-ci-runs-the-tests-in-a-freebsd-vm--01a1d4ff5f9a.md), [ADR-0028](/decisions/adr-0028-a-tag-push-builds-the-release-archives-on-linux--01a1fe97af71.md)

## Context
Each CI job and the release `dist` job downloaded Zig from ziglang.org. On 2026-11-25, ziglang.org sent partial files and closed connections. All five CI jobs of PR #6 and of `main` failed in the Zig download, and a person ran them again by hand. The Zig project asks CI to use its community mirrors and to keep the load off ziglang.org. The workflows pin the SHA-256 of each Zig archive.

## Decision
- `scripts/fetch-zig.sh FILE SHA256 OUT` downloads a Zig archive. Each job that needs Zig calls it: Linux, macOS, Windows, the FreeBSD VM and the release `dist` job.
- The script tries the community mirrors in a random order, then ziglang.org. The script keeps a copy of the mirror list (`https://ziglang.org/download/community-mirrors.txt`), so the list does not depend on ziglang.org.
- Each source has a time limit. curl stops a source that is slower than 50 kB/s for 30 s, or that takes more than 10 minutes. Then the script tries the next source.
- The script checks the pinned SHA-256 of each file. A file with a different checksum goes to the next source. A mirror cannot change the archive.
- The script uses POSIX sh, curl, awk and the checksum tool of the system (`sha256sum`, `shasum` or `sha256`). It runs on each CI system.

## Consequences
- A ziglang.org outage does not stop CI or a release.
- A mirror that is down or stale costs one failed attempt.
- The mirror list in the script can become old. Copy the current list into the script from time to time.
- GNU Make 4.3 still comes from ftp.gnu.org. A follow-up can add a fallback for it.

## Alternatives considered
- **Retry ziglang.org only.** Rejected: a retry does not help during a long outage, and it adds load to ziglang.org.
- **Read the mirror list from ziglang.org at run time.** Rejected: the list then depends on the server that is down.
- **The `mlugg/setup-zig` action.** Rejected: it does not run in the FreeBSD VM, and the workflows already pin each checksum.
- **Check the minisign signature, as the Zig project suggests.** Rejected for now: the pinned SHA-256 is a stronger check for one fixed version, and minisign is not on each runner.
