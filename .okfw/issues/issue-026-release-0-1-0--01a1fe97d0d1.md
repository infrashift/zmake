---
x-okfw-id: "01a1fe97-d0d1-7247-92e7-3e6daf1c9b49"
title: "ISSUE-026: Release 0.1.0"
type: "Issue"
x-okfw-kind: "issue"
tags:
  - "issue"
  - "phase-26"
  - "release"
  - "ci"
  - "closed"
x-okfw-created: "2026-11-21T08:52:04-06:00"
x-okfw-timestamp: "2026-11-21T08:54:35-06:00"
description: "zmake 0.1.0 ships as a draft GitHub release with static Linux amd64 and arm64 archives and a macOS arm64 archive, each with the man pages, SHA256SUMS and a provenance attestation."
---

# ISSUE-026: Release 0.1.0

**Status/Phase:** Closed · Phase 26

## Description
zmake had no binary release. Users had to install Zig 0.17.1 and build from source. Release 0.1.0 gives archives for Linux on amd64 and arm64 and for macOS on arm64. See [ADR-0028](/decisions/adr-0028-a-tag-push-builds-the-release-archives-on-linux--01a1fe97af71.md).

## Acceptance Criteria
- [x] `make dist` and `zmake dist` build three archives and `SHA256SUMS` in `zig-out/dist`. Each archive holds `bin/zmake`, the two man pages, `LICENSE` and `README.md`.
- [x] `scripts/dist.sh` stops when the version does not match `build.zig.zon`, or when a tracked file has a change.
- [x] The Linux binaries are static. The macOS binary has an ad-hoc signature.
- [x] `.github/workflows/release.yml` runs the CI gates, `make dist`, a check of each archive on a native runner, an attestation and a draft release.
- [x] `CHANGELOG.md` has a `## 0.1.0` section. `scripts/ste-check.py` checks it.
- [x] Getting Started and the README tell how to install a release. Contributing tells how to make a release.
- [x] `make check` and `zmake check` pass.

## Resolution
Done on 2026-11-21 in Phase 26 ([ADR-0028](/decisions/adr-0028-a-tag-push-builds-the-release-archives-on-linux--01a1fe97af71.md)).

- A test run of `scripts/dist.sh 0.1.0-rc.1` in a clean clone built the three archives. Each archive holds the expected files.
- `file` reports "statically linked" for both Linux binaries. The macOS binary has an `LC_CODE_SIGNATURE` load command with an embedded signature.
- The script stops on a version that does not match and on a changed tracked file.
- The verify step of `release.yml` passed on this host with the linux-amd64 archive. actionlint reports no issue in `release.yml`.
- The first release run on GitHub tests the arm64 and macOS runners, the attestation and the draft release.
