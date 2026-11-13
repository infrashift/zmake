---
id: "01a1d4cd-f854-770b-8fff-dde256910ebc"
title: "ADR-0022: A static pattern rule gives one explicit rule per target"
type: "ADR"
tags:
  - "adr"
  - "parser"
  - "rules"
created: "2026-11-13T06:07:10-06:00"
timestamp: "2026-11-13T06:07:10-06:00"
description: "A static pattern rule (objs: %.o: %.c) expands at read time into one explicit rule per target with its stem; $| gives the order-only prerequisites."
---

# ADR-0022: A static pattern rule gives one explicit rule per target

**Status:** Accepted
**Date:** 2026-11-13
**Source:** [ISSUE-020](/issues/issue-020-static-pattern-rules--01a1d399e029.md), [ADR-0005](/decisions/adr-0005-unsupported-directives-fail-loudly--01a1d30ae687.md)

## Context
Real Makefiles often use static pattern rules, for example `$(OBJS): %.o: %.c`. Since Phase 19, zmake stops at such a rule with a clear error. GNU Make 4.3 records one explicit rule for each target. The stem replaces `%` in each prerequisite, and `$*` gives the stem.

## Decision
- The parser keeps the target pattern on the rule (`RuleDecl.target_pattern`). A second top-level `:` before the `;` starts the prerequisite patterns.
- At read time, the database expands the targets, the pattern and the prerequisites. It adds one explicit rule for each target, with its stem (`Rule.stem`).
- The rest of zmake sees normal explicit rules. Merges with other rules, a pattern recipe for a rule without a recipe, double-colon rules, directory search and the default goal work as before.
- The stem replaces the first `%` of each normal and order-only prerequisite. A prerequisite without `%` does not change.
- The pattern matches the full target name, also the directory part.
- When the pattern does not match a target, zmake gives the GNU Make warning `target 'x' doesn't match the target pattern`. As in GNU Make, the target keeps the recipe, gets no prerequisites, and `$*` is the target name.
- Three errors stop the build with the GNU Make text: `missing target pattern`, `multiple target patterns` and `target pattern contains no '%'`.
- A target keeps the stem of its static pattern rule also when the recipe comes from another rule.
- `$|` gives the order-only prerequisites, without duplicates. Before this phase, `$|` was always empty.

## Consequences
- Acceptance scenario 21 compares a static pattern project with GNU Make 4.3. It runs a dry run, a build, an incremental build and `-j4`, and checks the warning and the errors.
- The graph and the executor need no new rule kind. Only the stem and the order-only list of a double-colon rule are new fields.
- `targets: pattern: NAME = value` stops with `invalid target-specific variable`. GNU Make reads `NAME` as a prerequisite there.

## Alternatives considered
- **A new kind of pattern rule in the graph.** Rejected: GNU Make records explicit rules, and the graph needs no change for them.
- **Keep the error.** Rejected: static pattern rules are common in real Makefiles.
