---
id: "01a1d34e-cd58-7b4b-a0cf-be318067e367"
title: "ISSUE-017: The options -k, -q, -t and -B"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-17"
  - "cli"
  - "open"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:08:39-06:00"
description: "Phase 17: keep going, question, touch and always-make, and combined short options."
---

# ISSUE-017: The options -k, -q, -t and -B

**Status/Phase:** Open · Phase 17

## Description
Add the common GNU Make options. Pass them to sub-makes through MAKEFLAGS.

## Acceptance Criteria
- [ ] `-k` continues with other targets after a failure. The exit code stays 2.
- [ ] `-q` runs nothing. The exit code is 0 when the goals are up to date, else 1.
- [ ] `-t` touches the out-of-date file targets and runs no recipe.
- [ ] `-B` treats every target as out of date.
- [ ] Combined short options such as `-kj4` and `-nB`.
- [ ] `make check` passes.

## Related
[PLAN.md](../../PLAN.md)
