---
id: "01a1d399-e029-72be-975e-ccefd085b7b9"
title: "ISSUE-020: Static pattern rules"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "follow-up"
  - "parser"
  - "open"
created: "2026-11-13T00:30:39-06:00"
timestamp: "2026-11-13T00:30:39-06:00"
description: "Static pattern rules (objs: %.o: %.c) give one explicit rule per target; today zmake stops with a clear error."
---

# ISSUE-020: Static pattern rules

**Status/Phase:** Open · follow-up, found in Phase 19

## Description
A static pattern rule applies a pattern to a fixed list of targets:

```make
$(OBJS): %.o: %.c
	$(CC) -c $< -o $@
```

Real Makefiles use this form often. zmake stops with `static pattern rules are not supported` since Phase 19. Before Phase 19, it read `%.o:` as a prerequisite and failed with a confusing message.

## Acceptance Criteria
- [ ] `targets: target-pattern: prerequisite-patterns` gives one explicit rule per target, with the stem in `$*`.
- [ ] A target that does not match the target pattern gives the GNU Make error.
- [ ] Order-only prerequisites and an inline recipe work.
- [ ] The dry run of a static pattern Makefile matches GNU Make in `tests/acceptance.sh`.
- [ ] `make check` passes.

## Related
[ADR-0005](/decisions/adr-0005-unsupported-directives-fail-loudly--01a1d30ae687.md) · [PLAN.md](../../PLAN.md)
