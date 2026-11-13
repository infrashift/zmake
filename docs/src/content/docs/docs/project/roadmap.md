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
| **9. Functions** | Text, file name, conditional, loop, variable and message functions | Done |
| **10. Reader** | Conditionals, `define`, `override`, `undefine` and `$(eval ...)` | Done |
| **11. Include** | `include`, `-include`, `sinclude`, `MAKEFILE_LIST`, file names in messages | Done |
| **12. Export** | `export`, `unexport`, `.EXPORT_ALL_VARIABLES`, the recipe environment | Done |
| **13. vpath** | `VPATH` and `vpath` directory search; paths in automatic variables | Done |
| **14. Target variables** | Target-specific and pattern-specific variables; GNU serial order | Done |
| **15. Double-colon rules** | Independent `::` rules per target | Done |
| **16. Built-ins** | Built-in variables and implicit rules, suffix rules, `-r`, `-R` | Done |
| **17. Options** | `-k`, `-q`, `-t`, `-B`, `-s` and option clusters | Done |
| **18. MAKEFLAGS quoting** | Values with spaces and backslashes reach sub-makes | Done |

## Follow-ups

These features are outside the current scope. Each one stops the build with an
error today:

- macOS and BSD support for the jobserver

