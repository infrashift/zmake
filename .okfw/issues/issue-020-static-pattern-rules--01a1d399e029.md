---
id: "01a1d399-e029-72be-975e-ccefd085b7b9"
title: "ISSUE-020: Static pattern rules"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "follow-up"
  - "parser"
  - "closed"
created: "2026-11-13T00:30:39-06:00"
timestamp: "2026-11-13T06:07:39-06:00"
description: "Static pattern rules (objs: %.o: %.c) give one explicit rule per target; today zmake stops with a clear error."
---

# ISSUE-020: Static pattern rules

**Status/Phase:** Closed · follow-up, found in Phase 19

## Description
A static pattern rule applies a pattern to a fixed list of targets:

```make
$(OBJS): %.o: %.c
	$(CC) -c $< -o $@
```

Real Makefiles use this form often. zmake stops with `static pattern rules are not supported` since Phase 19. Before Phase 19, it read `%.o:` as a prerequisite and failed with a confusing message.

## Acceptance Criteria
- [x] `targets: target-pattern: prerequisite-patterns` gives one explicit rule per target, with the stem in `$*`.
- [x] A target that does not match the target pattern gives the GNU Make error.
- [x] Order-only prerequisites and an inline recipe work.
- [x] The dry run of a static pattern Makefile matches GNU Make in `tests/acceptance.sh`.
- [x] `make check` passes.

## Resolution
Done on 2026-11-13 in Phase 20. `make check` passes.

- At read time, a static pattern rule becomes one explicit rule for each target, with its stem ([ADR-0022](/decisions/adr-0022-a-static-pattern-rule-gives-one-explicit-rule-per-target--01a1d4cdf854.md)).
- The stem replaces `%` in the normal and order-only prerequisites. `$*` gives the stem.
- A target that the pattern does not match gives the GNU Make warning. The three pattern errors stop with the GNU Make text.
- Found during the phase: `$|` was always empty. It now gives the order-only prerequisites.
- Acceptance scenario 21 compares a static pattern project with GNU Make 4.3. It runs a dry run, a build, an incremental build and `-j4`.
- The scenario also compares a double-colon rule, a pattern recipe, an inline recipe, the warning and the errors.

## Related
[ADR-0005](/decisions/adr-0005-unsupported-directives-fail-loudly--01a1d30ae687.md) · [PLAN.md](../../PLAN.md)
