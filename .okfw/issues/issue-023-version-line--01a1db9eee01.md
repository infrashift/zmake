---
id: "01a1db9e-ee01-7612-9f81-83d2019c6230"
title: "ISSUE-023: Version line"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-23"
  - "cli"
  - "closed"
created: "2026-11-14T13:53:08-06:00"
timestamp: "2026-11-14T13:53:28-06:00"
description: "zmake -v and zmake --version print zmake VERSION (COMMIT) and exit 0, so a script can check the commit of an installed binary."
---

# ISSUE-023: Version line

**Status/Phase:** Closed · Phase 23

## Description
A sibling repository pins zmake to a commit in its tool lock file. Its tool check cannot read the commit of an installed binary. `zmake --version` stops with `unknown option '--version'` and exit code 2. GNU Make 4.3 prints its version for `-v` and `--version` and exits 0.

## Acceptance Criteria
- [x] `zmake --version` and `zmake -v` print one line to stdout and exit 0: `zmake VERSION (COMMIT)`.
- [x] zmake prints the line before it reads an input file, also with targets, other options or `-C`.
- [x] VERSION comes from `.version` in `build.zig.zon`.
- [x] COMMIT is the full `git rev-parse HEAD`, with `-dirty` for a change to a tracked file.
- [x] COMMIT is `unknown` without git or without `.git`. The build does not fail.
- [x] Unit tests and acceptance scenario 22 fail without the option.
- [x] The README, the CLI docs page and the [CLI contract](/specs/cli-contract--01a1d30ae665.md) show the option.
- [x] `make check` and `zmake check` pass.

## Resolution
Done on 2026-11-14 in Phase 23 ([ADR-0025](/decisions/adr-0025-the-version-line-names-the-git-commit-of-the-build--01a1db9effa4.md)).

- `src/cli.zig` parses `-v` (also in a cluster) and `--version`. `cli.versionLine` formats the line.
- `src/main.zig` prints the line, then the usage under `-h`, and exits 0.
- `build.zig` adds a `build_options` module with `version` and `commit`. It runs git in the configure phase and poisons the configure cache.
- Acceptance scenario 22 compares the line with `build.zig.zon` and `git rev-parse HEAD`, and the exit codes with GNU Make 4.3.
- Checks by hand: a clean clone gives the bare commit, a changed tracked file gives `-dirty`, a new untracked file gives no suffix. A tarball, also inside another git repository, gives `unknown`. A `PATH` without git gives `unknown`.

## Related
[ADR-0025](/decisions/adr-0025-the-version-line-names-the-git-commit-of-the-build--01a1db9effa4.md) · [ADR-0019](/decisions/adr-0019-letter-flags-share-one-table-for-options-and-makeflags--01a1d390363b.md) · [CLI contract](/specs/cli-contract--01a1d30ae665.md) · [PLAN.md](../../PLAN.md)
