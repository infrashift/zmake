---
x-okfw-id: "01a1fe97-af71-7ebd-97e8-a535bd3425ad"
title: "ADR-0028: A tag push builds the release archives on Linux"
type: "ADR"
tags:
  - "adr"
  - "release"
  - "ci"
  - "install"
x-okfw-created: "2026-11-21T08:51:56-06:00"
x-okfw-timestamp: "2026-11-21T08:51:56-06:00"
description: "A push of a vX.Y.Z tag runs the CI gates, cross-builds static Linux amd64 and arm64 and ad-hoc signed macOS arm64 archives with make dist, runs each on a native runner, and makes a draft release with SHA256SUMS and a provenance attestation."
---

# ADR-0028: A tag push builds the release archives on Linux

**Status:** Accepted
**Date:** 2026-11-21
**Source:** User request: release zmake 0.1.0 for Linux on amd64 and arm64, and for macOS on arm64.

## Context
zmake had no binary release. Users built it from source with Zig 0.17.1. The version in `build.zig.zon` is `0.1.0`, and `zmake --version` names the git commit of the build ([ADR-0025](/decisions/adr-0025-the-version-line-names-the-git-commit-of-the-build--01a1db9effa4.md)).

- On Linux, zmake links no libc. It makes system calls through `std.os.linux`. A Linux build is a static binary.
- Zig cross-compiles all three targets on one Linux host. `make cross` already does this for macOS and FreeBSD ([ADR-0020](/decisions/adr-0020-a-named-fifo-shares-the-jobserver-off-linux--01a1d399e000.md)).
- On Apple silicon, the kernel runs only signed code. The Zig linker adds an ad-hoc signature to an `aarch64-macos` binary. A test build has an `LC_CODE_SIGNATURE` load command with an embedded signature.
- Gatekeeper adds a quarantine flag to a file that a browser downloads. Only a Developer ID signature and notarization remove the warning. These need an Apple Developer account and secrets in CI.
- The repository is public. GitHub-hosted arm64 Linux runners and build-provenance attestations are free for it.

## Decision
- A push of a tag `vX.Y.Z` starts `.github/workflows/release.yml`. The workflow has four jobs:
  1. **ci** runs every gate of `ci.yml` on the tagged commit (`workflow_call`).
  2. **dist** runs `make dist VERSION=X.Y.Z` on `ubuntu-24.04`.
  3. **verify** unpacks each archive on a native runner (`ubuntu-24.04`, `ubuntu-24.04-arm`, `macos-latest`). It checks the checksum, the version line and the man pages. On Linux, it checks the static link. On macOS, it checks the ad-hoc signature. Then it runs one legacy-mode and one modern-mode file.
  4. **release** makes a build-provenance attestation for the archives and a **draft** release with the notes from `CHANGELOG.md`. A person reads the draft and publishes it. A tag with a `-` makes a pre-release.
- `scripts/dist.sh` builds the archives. The `dist` target of the Makefile and the ZMakefile runs it ([ADR-0010](/decisions/adr-0010-keep-a-modern-mode-zmakefile-next-to-the-makefile--01a1d348f8d1.md)). The script stops when the version does not match `build.zig.zon`, or when a tracked file has a change. On a Linux x86_64 host, it also checks the version line of the amd64 binary.
- The targets are `x86_64-linux-musl`, `aarch64-linux-musl` and `aarch64-macos`. All three are `ReleaseSafe` builds (`zig build --release`), so the assertions stay active ([ADR-0003](/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md)).
- The archive names are `zmake-vX.Y.Z-linux-amd64.tar.gz`, `zmake-vX.Y.Z-linux-arm64.tar.gz` and `zmake-vX.Y.Z-macos-arm64.tar.gz`, as in the okfw releases. Each archive holds one directory with `bin/zmake`, `share/man/man1/zmake.1`, `share/man/man5/zmakefile.5`, `LICENSE` and `README.md`. `zig build -p` makes this layout ([ADR-0027](/decisions/adr-0027-man-pages-are-mdoc-files-installed-under-the-prefix--01a1f58f63a3.md)).
- A `SHA256SUMS` file goes with the archives. Users check an archive with `sha256sum -c` or with `gh attestation verify`.
- The macOS binary has only the ad-hoc signature from the linker.

## Consequences
- A release needs no secrets. The workflow uses only the `GITHUB_TOKEN`.
- A macOS user who downloads an archive with a browser must remove the quarantine flag (`xattr -d com.apple.quarantine`). A download with `curl` gets no flag. The Getting Started page tells how.
- FreeBSD and x86_64 macOS have no archive. Users on these systems build from source.
- The binaries keep their debug information. The archives are larger, but a stack trace from a safety check shows file names and line numbers.
- A release of a new version changes `build.zig.zon` and `CHANGELOG.md` before the tag.

## Alternatives considered
- **Developer ID signature and notarization.** Deferred: it needs an Apple Developer account and secrets in CI. A later release can add it with no change to the archive layout.
- **A native build on each runner.** Rejected: Zig cross-compiles from one host. One build host gives one toolchain and one log. The native runners still run each binary.
- **A raw binary with no archive.** Rejected: the man pages and the license do not go with a raw binary.
- **Publish the release with no review.** Rejected for now: a draft lets a person read the notes and the assets of the first releases.
