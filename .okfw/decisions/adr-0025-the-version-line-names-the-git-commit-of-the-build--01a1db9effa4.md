---
id: "01a1db9e-ffa4-7254-b716-e2d510387392"
title: "ADR-0025: The version line names the git commit of the build"
type: "ADR"
tags:
  - "adr"
  - "cli"
  - "build"
created: "2026-11-14T13:53:12-06:00"
timestamp: "2026-11-14T13:53:12-06:00"
description: "zmake -v and --version print zmake VERSION (COMMIT); build.zig takes VERSION from build.zig.zon and COMMIT from git, with -dirty or unknown."
---

# ADR-0025: The version line names the git commit of the build

**Status:** Accepted
**Date:** 2026-11-14
**Source:** Phase 23, [ISSUE-023](/issues/issue-023-version-line--01a1db9eee01.md)

## Context
Another repository pins zmake to a commit. Its tool check cannot read the commit of an installed binary, because zmake has no version output. `zmake --version` stops with `unknown option`. GNU Make 4.3 prints its version for `-v` and `--version`, and exits 0 before it reads a makefile.

## Decision
- `-v` and `--version` set `Options.version` in `src/cli.zig`. `-v` can be part of a short option cluster, for example `-nv`. `v` is not a `MAKEFLAGS` letter, so a sub-make gets no `v`.
- `src/main.zig` prints one line to stdout and exits 0: `zmake VERSION (COMMIT)`. It prints the line before it changes the directory or reads an input file. It ignores the targets and the other options, as GNU Make does. With `-h`, the usage comes after the line.
- `build.zig` gives the values to the binary through a `build_options` module. VERSION is `.version` from `build.zig.zon`.
- COMMIT is `git rev-parse HEAD`, 40 hex digits (64 for a SHA-256 repository). When `git status --porcelain --untracked-files=no` shows a change, COMMIT gets the suffix `-dirty`. This is the rule of `git describe --dirty`: an untracked file does not add the suffix.
- COMMIT is `unknown` when the build root has no `.git`, when git is not on the `PATH`, or when a git command fails. The build does not fail. The `.git` check stops git from finding a parent repository of an unpacked source tarball.
- The git result depends on state that the Zig 0.17 configure cache cannot track. `build.zig` calls `b.graph.poisonCache()`, so the configure phase runs on each `zig build`, and the commit is never stale.

## Consequences
- A script can compare the commit in `zmake --version` with a pinned commit.
- Each `zig build` runs two git commands in the configure phase. The configure cache is not used.
- A binary from a work tree with changes shows `-dirty`. A binary from a tarball shows `unknown`.
- Acceptance scenario 22 checks the line, the `build.zig.zon` version, the git HEAD and the GNU Make exit codes.

## Alternatives considered
- **Run git in a make-phase `Run` step.** Rejected: a missing git fails the step, and a shell wrapper adds a dependency on `sh` to the build.
- **`git describe --always --dirty`.** Rejected: with a tag, it gives `TAG-N-gHASH`, not the full commit.
- **Count untracked files as dirty.** Rejected: a file that git does not track cannot change the binary unless a tracked file imports it, and that change already adds `-dirty`.
- **A `-Dcommit` build option to set the commit.** Not added: no caller needs it yet.
