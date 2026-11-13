---
id: "01a1d35f-6009-75f9-b738-6f0b303d67c7"
title: "ADR-0011: Lazy functions use staged calls on the frame stack"
type: "ADR"
tags:
  - "adr"
  - "eval"
  - "functions"
created: "2026-11-12T23:26:45-06:00"
timestamp: "2026-11-12T23:26:45-06:00"
description: "if, and, or, intcmp, foreach, let and call expand their arguments and bodies in stages on the explicit frame stack, with scoped variable bindings and no recursion."
---

# ADR-0011: Lazy functions use staged calls on the frame stack

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Phase 9, [ISSUE-009](/issues/issue-009-text-control-and-file-functions--01a1d34ecd22.md), [ADR-0006](/decisions/adr-0006-expansion-uses-an-explicit-frame-stack--01a1d31ab339.md)

## Context
`if`, `and`, `or` and `intcmp` must not expand the arguments that they do not use: an unused `$(error ...)` must not fire. `foreach`, `let` and `call` bind variables and expand a body one or more times. `call` can call itself, for example a `reverse` function. Rule R1 forbids recursion, so the evaluator cannot call `expand` from a function.

## Decision
- A pending call on a frame has a `stage`. In the `args` stage, the frame expands one argument at a time in a child frame. After each argument, `advance` decides the next step: the next argument, a branch, a loop body or the call.
- `if` and `intcmp` choose one argument and expand only that one. `and` and `or` stop at the first empty or non-empty argument.
- `foreach`, `let` and `call` open a `Scope`. The scope saves the definitions that the bindings shadow. The body expands in a child frame (the `body` stage). `foreach` pushes the body again for each word. When the body ends, the scope restores the saved definitions, last name first.
- `call` binds `$(0)` to `$(15)`. A missing argument is empty, so an inner call hides the arguments of an outer call, as in GNU Make. A simple variable gives its value without expansion. A built-in function name calls the function with the arguments, each `$` escaped as `$$`.
- The body frame of `call` has no variable name, so a recursive `call` does not trigger the recursive-variable error. The frame limit of 64 bounds the recursion depth.
- One call takes at most 16 arguments (`limits.function_args_max`). A fixed-arity function keeps the extra commas in its last argument, as in GNU Make.
- The eager functions live in `src/builtins.zig`. The pure word and file name functions live in `src/textfns.zig`. Nothing there calls `expand`, so the call graph stays acyclic.
- A line without a separator that contains `$`, for example `$(info text)`, is an expression statement. The loader expands it. A non-empty result is the error `missing separator`.

## Consequences
- The output of each function matches GNU Make 4.3 in acceptance scenario 10. `let` and `intcmp` follow the GNU Make 4.4 manual.
- `eval` waits for the reader of Phase 10. `guile` stays unsupported.

## Alternatives considered
- **Expand all arguments, then decide.** Rejected: an unused `$(error ...)` fires, and `$(if ...)` with a costly `$(shell ...)` runs it for nothing.
- **A separate evaluator call for each body.** Rejected: it is recursion through `expand`, which rule R1 forbids.
