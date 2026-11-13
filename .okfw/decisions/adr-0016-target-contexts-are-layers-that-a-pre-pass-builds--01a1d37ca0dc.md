---
id: "01a1d37c-a0dc-78fd-8be3-d2e31f34493a"
title: "ADR-0016: Target contexts are layers that a pre-pass builds"
type: "ADR"
tags:
  - "adr"
  - "eval"
  - "executor"
  - "target-variables"
created: "2026-11-12T23:58:42-06:00"
timestamp: "2026-11-12T23:58:42-06:00"
description: "Each node inherits the variable layers of its first parent, minus private variables, plus its own layer; a pass from the goals down builds them, and the evaluator reads layers first."
---

# ADR-0016: Target contexts are layers that a pre-pass builds

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Phase 14, [ISSUE-014](/issues/issue-014-target-specific-and-pattern-specific-variables--01a1d34ecd43.md)

## Context
`target: VAR = value` sets a variable for the recipe of a target and for the prerequisites that the target builds. `%.o: VAR = value` does the same for each target that matches. GNU Make builds a shared prerequisite once, in the context of the target that first needs it. `private` stops the inheritance. `+=` adds to the value that the target sees otherwise. A command-line variable wins unless the assignment has `override`.

## Decision
- The parser reads `targets: [override] [export] [private] NAME op value` as a `target_var` statement. A `;` before the first `=` keeps the line a rule with an inline recipe.
- The database keeps the assignments per target name and a list of pattern assignments, in file order. The value stays unexpanded.
- The graph search records the first parent of each node (`dag.Node.parent`), in depth-first order, as GNU Make does.
- `src/context.zig` builds the layers of each node before the first job. It visits `graph.order` from the end, so a parent always has its context before its prerequisites. A node gets the layers of its parent without the `private` variables, plus one layer of its own. The own layer applies the matching pattern assignments (longer stem first) and then the target assignments, in file order.
- `Evaluator.lookup` reads `ev.layers` before the global variables. The executor sets the layers of a node while it expands the recipe and builds the environment.
- `:=` expands when the layer is built, with the layers below in effect. `+=` keeps the flavor of the value below. `?=` sets only an undefined variable.
- An exported name, or a variable with the `export` modifier, goes to the recipe environment with the value of the target.
- The ready queue of the executor became a priority queue on the position in `graph.order`. A serial build now runs in the depth-first post-order of GNU Make. The acceptance probe found this difference.

## Consequences
- Acceptance scenario 15 compares 13 lines of output with GNU Make 4.3. They cover values, inheritance, `private`, the command line, `export`, `?=`, the stem order and the run order. All match.
- A Makefile without target-specific variables builds no layers and has no extra cost.

## Alternatives considered
- **Compute the context when the recipe runs, from the node up to the goal.** Rejected: the parent of a node runs after the node, and a walk up the chain is a loop per node. The pre-pass gives each node its layers once.
- **Copy all global variables into each layer.** Rejected: memory grows with the number of targets.
