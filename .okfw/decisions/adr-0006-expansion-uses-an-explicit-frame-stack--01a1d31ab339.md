---
id: "01a1d31a-b339-71f3-9a6e-f9b5136e1b54"
title: "ADR-0006: Expansion uses an explicit frame stack"
type: "ADR"
tags:
  - "adr"
  - "eval"
  - "safety"
created: "2026-11-12T22:11:44-06:00"
timestamp: "2026-11-12T22:11:44-06:00"
description: "Variable and function expansion runs on a fixed-size frame stack instead of recursion, to satisfy Power of 10 rule R1."
---

# ADR-0006: Expansion uses an explicit frame stack

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Phase 3, [ADR-0003](/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md) rule R1

## Context
Make expansion nests. A recursive value can refer to a variable whose value refers to another variable. Functions take arguments that also need expansion. The natural design is a recursive function. Rule R1 forbids recursion.

## Decision
- `Evaluator.expand` keeps an explicit stack of frames. The stack holds at most 64 frames (`limits.expansion_depth_max`).
- Each frame expands one string. It copies literal text and starts one reference at a time.
- Some references need expansion first, for example `$($(X))` or `$(subst a,b,$(Y))`. Such a reference sets a `pending` call on the frame. Then it pushes a child frame for the first argument.
- When a child frame ends, `deliver` gives its result to the parent. The parent stores the result, pushes the next argument, or applies the call.
- The value of a recursive variable gets its own frame with the variable name. A second frame for the same name is the GNU error `Recursive variable 'X' references itself (eventually)`.
- The loop stops after 10,000,000 steps. The output of one expansion stops at 4 MiB.

## Consequences
- The call graph has no cycle. `nasa-lint.py` checks it.
- A frame with a pending call always has a child frame above it. So the top frame never has a pending call. `expand` asserts this.
- The error for a recursive variable shows the line that uses the variable. GNU Make shows the line that defines it.

## Alternatives considered
- **Recursive descent with a depth counter.** Rejected: rule R1.
- **Translate the text to a token list first, then evaluate.** Rejected: computed names such as `$($(X))` need expansion before the parser knows the name.
