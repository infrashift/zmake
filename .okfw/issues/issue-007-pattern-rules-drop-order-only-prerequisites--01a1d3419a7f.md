---
id: "01a1d341-9a7f-7f16-abb8-66b2c0abccda"
title: "ISSUE-007: Pattern rules drop order-only prerequisites"
type: "Issue"
kind: "issue"
tags:
  - "issue"
  - "bug"
  - "dag"
  - "closed"
created: "2026-11-12T22:54:14-06:00"
timestamp: "2026-11-12T23:10:26-06:00"
description: "A pattern rule loses its order-only prerequisites, so obj/%.o: src/%.c | obj never creates obj/."
---

# ISSUE-007: Pattern rules drop order-only prerequisites

**Status/Phase:** Closed · bug, found in Phase 6

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
- [x] A pattern rule keeps its order-only prerequisites. zmake expands `%` in them with the stem.
- [x] A test in `tests/legacy_test.zig` covers the example above.
- [x] The dry run of the example matches GNU Make in `tests/acceptance.sh`.

## Resolution
Done on 2026-11-12 in Phase 8. `make check` passes.

- `src/dag.zig`: `Match` carries the order-only prerequisites of the rule, with the stem applied. A pattern node and an explicit rule that takes its recipe from a pattern both keep them.
- GNU Make also checks the order-only prerequisites when it decides whether a pattern rule applies. zmake now does the same.
- Tests: a unit test in `src/dag.zig` and scenario 9 in `tests/acceptance.sh`, which compares the dry run with GNU Make.
- Known difference: GNU Make deletes an intermediate file that a chained pattern rule made. zmake keeps it.

## Related
[ISSUE-004](/issues/issue-004-dependency-graph-pattern-rules-and-cycle-detection--01a1d30ae6a0.md) · [Syntax modes and target kinds](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md)
