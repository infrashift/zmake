---
id: "01a1d30a-e67c-7342-8cc5-9d751de24c4a"
title: "ADR-0003: Adapt the NASA Power of 10 rules to Zig"
type: "ADR"
tags:
  - "adr"
  - "safety"
  - "lint"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "zmake follows the NASA/JPL Power of 10 rules where Zig and the problem allow; nasa-lint.py enforces the checkable rules."
---

# ADR-0003: Adapt the NASA Power of 10 rules to Zig

**Status:** Accepted
**Date:** 2026-11-12
**Source:** User request. Gerard J. Holzmann, "The Power of 10: Rules for Developing Safety-Critical Code" (2006).

## Context
The user requires the Power of 10 rules where possible. The rules target C. A Make tool reads inputs of unknown size, and Make variable expansion is recursive by nature. Some rules need an adaptation.

## Decision
| Rule | zmake adaptation | Check |
|---|---|---|
| R1 Simple control flow, no recursion | Zig has no `goto`. The evaluator and the DAG use explicit stacks with a fixed depth limit. | `nasa-lint.py` call graph |
| R2 Fixed loop bounds | Loops iterate over slices or count toward a limit. A loop that reaches its limit returns an error. | `nasa-lint.py` bans `while (true)` |
| R3 No allocation after initialization | Deviation: zmake allocates from one arena per invocation and frees nothing before exit. Hard limits cap the arena. | Review |
| R4 Short functions | A function has 60 lines or fewer. | `nasa-lint.py` |
| R5 Assertion density | An average of two or more `assert` calls per function. Assertions have no side effects. | `nasa-lint.py` |
| R6 Smallest scope | Declare data in the smallest block. The compiler rejects unused locals. | Compiler, review |
| R7 Check return values | Zig forces error handling. Do not use `catch {}`, `else |_| {}`, `catch unreachable` or `_ = f()` without a reason. Validate parameters with `assert`. | `nasa-lint.py` |
| R8 Limited preprocessor | Zig has no preprocessor. Use `comptime` for constants and types only. Do not use `@cImport`. | Review |
| R9 Restricted pointers | Do not add function pointers or vtables. zmake calls the `std.Io` vtable but adds none. | `nasa-lint.py` |
| R10 Zero warnings | Zig reports errors, not warnings. `make lint` runs `zig fmt --check` and `nasa-lint.py` on every change. | `make lint` |

**Hard limits** (`src/ast.zig`, `limits`): input file size 16 MiB, expansion depth 64, prerequisite depth 1024, graph nodes 65536.

**Release builds** use `ReleaseSafe`, so `assert` stays active in the shipped binary.

**Suppression:** `// nasa-lint: allow(Rn) <reason>` on the line or the line above. Each suppression needs a reason.

## Consequences
- The code is more verbose: explicit stacks and many assertions.
- An input that exceeds a limit fails with a clear error. GNU Make accepts it.
- Test blocks and test helpers are exempt from R4 and R5. A test helper has a name that starts with `test` or ends with `Test`.
- `nasa-lint.py --verbose` lists each function with fewer than two assertions.
- Assertions check programmer errors only. zmake reports bad input with an error, not with an assertion.

## Alternatives considered
- **Recursive expansion with a depth counter.** Rejected: R1 forbids recursion. A depth counter does not make a call graph acyclic.
- **Static buffers sized at startup.** Rejected: zmake cannot know the size of the input file before it reads it. The arena with hard limits gives the same bound.
