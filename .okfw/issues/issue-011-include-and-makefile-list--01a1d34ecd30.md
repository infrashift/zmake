---
id: "01a1d34e-cd30-7007-88e4-a0de3bc256fb"
title: "ISSUE-011: include and MAKEFILE_LIST"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-11"
  - "reader"
  - "open"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:08:39-06:00"
description: "Phase 11: include, -include and sinclude, with an explicit include stack, and MAKEFILE_LIST."
---

# ISSUE-011: include and MAKEFILE_LIST

**Status/Phase:** Open · Phase 11

## Description
Read other input files at the point of the directive. Messages name the file and the line of each statement.

## Acceptance Criteria
- [ ] `include FILES`, `-include FILES` and `sinclude FILES`. A missing file stops `include` with the GNU message.
- [ ] An explicit stack holds the open files, with a depth limit. No recursion.
- [ ] Each recipe line and each message carries the name of its own file.
- [ ] `MAKEFILE_LIST` lists each file that zmake read.
- [ ] zmake does not remake an included file. The docs state the limit.
- [ ] `make check` passes.

## Related
[PLAN.md](../../PLAN.md)
