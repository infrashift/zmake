---
x-okfw-id: "01a1ec7f-697a-79d6-aced-cb08e86b0e4d"
title: "ADR-0026: semscope checks the Power of 10 rules"
type: "ADR"
tags:
  - "adr"
  - "lint"
  - "power-of-10"
  - "tooling"
x-okfw-created: "2026-11-17T20:32:15-06:00"
x-okfw-timestamp: "2026-11-17T20:32:15-06:00"
description: "make lint runs semscope with the nasa-p10 ruleset on src/ when semscope is installed, and scripts/nasa-lint.py when it is not."
---

# ADR-0026: semscope checks the Power of 10 rules

**Status:** Accepted
**Date:** 2026-11-17
**Source:** User request: use semscope in the lint target in place of `nasa-lint.py`.

## Context
`make lint` ran `scripts/nasa-lint.py`. The script checks six of the ten rules of [ADR-0003](/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md) with regular expressions. semscope is a static checker in a sibling repository. Its ruleset `nasa-p10` checks all ten rules with a Tree-sitter parser. On zmake `src/`, semscope and `nasa-lint.py` give the same findings for the six shared rules, with 306 functions and 614 assertions in both. semscope uses `nasa-lint.py` as its Zig oracle, so the two copies of the script stay byte-identical.

The semscope repository has no remote yet. The CI runners cannot install it.

## Decision
- `make lint` and `zmake lint` run `semscope scan -r nasa-p10 -r .semscope.cue --fail-level warning src` when `semscope` is on the `PATH`.
- When `semscope` is not on the `PATH`, the task prints a note and runs `scripts/nasa-lint.py`. CI uses this path.
- The variable `SEMSCOPE` names the command. The default is `semscope`.
- `.semscope.cue` turns off NASA-P10-03, because ADR-0003 records the arena allocation as a deviation.
- semscope checks the rules R6, R8 and R10 too. Its first scan found one `@ptrCast` in `src/jobserver.zig`. Phase 24 removes the cast.
- The task scans `src/` only, the same files as `nasa-lint.py`.

## Consequences
- A local run checks ten rules. A CI run checks six rules until CI installs semscope.
- `scripts/nasa-lint.py` stays in the repository as the fallback.
- A suppression can use `// semscope: allow(NASA-P10-04) <reason>` or the old tag `// nasa-lint: allow(R4) <reason>`. semscope reads both.
- semscope is a development tool, not a dependency of the zmake binary.

## Alternatives considered
- **semscope only.** Rejected for now: CI cannot install semscope.
- **nasa-lint.py only.** Rejected: it checks six rules, and semscope found a defect that it cannot see.
