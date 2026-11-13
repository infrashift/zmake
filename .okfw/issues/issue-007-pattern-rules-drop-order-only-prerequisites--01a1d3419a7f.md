---
id: "01a1d341-9a7f-7f16-abb8-66b2c0abccda"
title: "ISSUE-007: Pattern rules drop order-only prerequisites"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "bug"
  - "dag"
  - "open"
created: "2026-11-12T22:54:14-06:00"
timestamp: "2026-11-12T22:54:14-06:00"
description: "A pattern rule loses its order-only prerequisites, so obj/%.o: src/%.c | obj never creates obj/."
---

# ISSUE-007: Pattern rules drop order-only prerequisites

**Status/Phase:** Open · bug, found in Phase 6

## Description
A pattern rule loses its order-only prerequisites. `src/dag.zig` builds the node for a pattern match with `.order_only = &.{}`, so zmake never builds the order-only prerequisites of the pattern rule.

```make
obj/%.o: src/%.c | obj
	$(CC) -c $< -o $@
obj:
	mkdir -p $@
```

GNU Make runs `mkdir -p obj` before the first compile. zmake does not run it, and the compile fails with `can't create obj/main.o`. Order-only prerequisites on explicit rules work.

## Acceptance Criteria
- [ ] A pattern rule keeps its order-only prerequisites. zmake expands `%` in them with the stem.
- [ ] A test in `tests/legacy_test.zig` covers the example above.
- [ ] The dry run of the example matches GNU Make in `tests/acceptance.sh`.

## Related
[ISSUE-004](/issues/issue-004-dependency-graph-pattern-rules-and-cycle-detection--01a1d30ae6a0.md) · [Syntax modes and target kinds](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md)
