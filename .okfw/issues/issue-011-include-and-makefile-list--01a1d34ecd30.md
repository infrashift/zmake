---
id: "01a1d34e-cd30-7007-88e4-a0de3bc256fb"
title: "ISSUE-011: include and MAKEFILE_LIST"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "phase-11"
  - "reader"
  - "closed"
created: "2026-11-12T23:08:39-06:00"
timestamp: "2026-11-12T23:44:01-06:00"
description: "Phase 11: include, -include and sinclude, with an explicit include stack, and MAKEFILE_LIST."
---

# ISSUE-011: include and MAKEFILE_LIST

**Status/Phase:** Closed · Phase 11

## Description
Read other input files at the point of the directive. Messages name the file and the line of each statement.

## Acceptance Criteria
- [x] `include FILES`, `-include FILES` and `sinclude FILES`. A missing file stops `include` with the GNU message.
- [x] An explicit stack holds the open files, with a depth limit. No recursion.
- [x] Each recipe line and each message carries the name of its own file.
- [x] `MAKEFILE_LIST` lists each file that zmake read.
- [x] zmake does not remake an included file. The docs state the limit.
- [x] `make check` passes.

## Resolution
Done on 2026-11-12 in Phase 11. `make check` passes.

- `include`, `-include` and `sinclude` read each file as a source on the reader stack ([ADR-0013](/decisions/adr-0013-include-files-share-the-source-stack-and-are-not-remade--01a1d36e9f70.md)). Names with glob characters expand as in GNU Make.
- `ast.RuleDecl`, `ast.Rule` and `dag.Node` carry the file of each rule. Recipe errors, override warnings, cycle messages and read-time errors name the right file.
- `MAKEFILE_LIST` lists each file when zmake starts to read it.
- A missing `include` file stops zmake after all input, with the GNU Make messages. zmake does not remake included files and says so when a rule exists.
- Acceptance scenario 12 matches GNU Make 4.3, also for the error messages.

## Related
[PLAN.md](../../PLAN.md)
