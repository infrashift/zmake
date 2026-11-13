---
title: Roadmap
description: The zmake phases. The project wiki tracks each phase as an issue.
---

`PLAN.md` holds a checklist for each phase. The project wiki (`.okfw/issues/`)
holds a mirror issue for each phase. Each phase lands as one tested commit.

| Phase | Scope | Status |
|---|---|---|
| **0. Bootstrap** | Zig toolchain, repository, Makefile, OKF wiki, lint scripts | Done |
| **1. Scaffolding** | `build.zig`, the AST, input file discovery and the CLI options | Done |
| **2. Parser** | Context-sensitive lexer, dual-mode parser, `@name:` and `task name:` | Done |
| **3. Evaluator** | Immediate and deferred expansion, automatic variables, four functions, target classifier | Done |
| **4. Graph** | Goal resolution, pattern rules, cycle detection, topological order | Done |
| **5. Executor** | Modification time checks, `-jN` scheduler, GNU Make jobserver, acceptance suite | Done |
| **6. Docs site** | This site, the landing-page demo, the GitHub Pages deploy | Done |
| **7. Modern ZMakefile** | The zmake repo runs its own gates through a modern-mode `ZMakefile` | Done |
| **8. Order-only fix** | Pattern rules keep their order-only prerequisites | Done |

## Follow-ups

These features are outside the current scope. Each one stops the build with an
error today:

- `include`, conditionals, `define`, `export` and `vpath`
- Built-in implicit rules and built-in variables such as `CC`, suffix rules, double-colon rules and target-specific variables
- Functions other than `wildcard`, `shell`, `patsubst` and `subst`
- The options `-k` (keep going), `-q`, `-t` and `-B`
- Quoted values with spaces in `MAKEFLAGS` overrides
- macOS and BSD support for the jobserver

