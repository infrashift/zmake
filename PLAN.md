# PLAN.md — zmake

zmake is a Make-compatible build tool in Zig 0.17.1. It has two syntax modes:

- **Legacy mode** (`Makefile`, `makefile`, `GNUmakefile`) keeps strict POSIX and GNU Make semantics.
- **Modern mode** (`ZMakefile`, `Make.zig.mk`, `--modern`) removes `.PHONY` boilerplate. It adds `@task` syntax, phony inference and space-indented recipes.

Work on one phase at a time (`CLAUDE.md` rule 1). Each phase has a mirror issue in the OKF wiki (`.okfw/issues/`). When a phase is done, tick this checklist and the acceptance criteria of the issue.

Loop: implement → `make lint test` → repeat until green → update the wiki → `make wiki docs-style` → commit.

- Architecture: [zmake architecture overview](.okfw/architecture/zmake-architecture-overview--01a1d30ae65a.md)
- Specs: [Syntax modes and target kinds](.okfw/specs/syntax-modes-and-target-kinds--01a1d30ae660.md) · [CLI contract](.okfw/specs/cli-contract--01a1d30ae665.md) · [Jobserver protocol](.okfw/specs/jobserver-protocol--01a1d30ae66b.md)
- Decisions: [ADR-0006 frame stack](.okfw/decisions/adr-0006-expansion-uses-an-explicit-frame-stack--01a1d31ab339.md) · [ADR-0007 partial targets](.okfw/decisions/adr-0007-delete-partial-targets-by-mode--01a1d327df21.md) · [ADR-0008 jobserver](.okfw/decisions/adr-0008-take-jobserver-tokens-through-a-private-non-blocking-descriptor--01a1d327df28.md)
- Docs: [ADR-0009 docs site](.okfw/decisions/adr-0009-document-zmake-with-astro-starlight-on-github-pages--01a1d33eea33.md) · https://infrashift.github.io/zmake/
- Rules: [ADR-0003 Power of 10](.okfw/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md) · ASD-STE100 for all documentation

## Phase 0 — Bootstrap
- [x] Install Zig 0.17.1 into `~/.local/zig/` and verify the SHA-256 sum ([ADR-0002](.okfw/decisions/adr-0002-zig-0-17-1-standard-library-only-linux-first--01a1d30ae676.md))
- [x] Create the git repo, `.gitignore`, `Makefile`, `CLAUDE.md` and `.mcp.json`
- [x] Create the OKF wiki (`okfw init`, `okfw install --platform claude`) ([ADR-0001](.okfw/decisions/adr-0001-adopt-an-okf-wiki-okfw-for-project-knowledge--01a1d30ae670.md))
- [x] Seed the wiki: guides, architecture, specs, ADR-0001 to ADR-0005, ISSUE-001 to ISSUE-005
- [x] Add the lint scripts `scripts/nasa-lint.py` and `scripts/ste-check.py`

## Phase 1 — Scaffolding, AST and input file discovery
Tracking: [ISSUE-001](.okfw/issues/issue-001-scaffolding-ast-and-input-file-discovery--01a1d30ae68d.md)
- [x] `build.zig` with the steps `install`, `test` and `acceptance`; `build.zig.zon` pins Zig 0.17.1
- [x] `src/ast.zig`: `SyntaxMode`, `TargetKind`, `VariableFlavor`, `Variable`, `RecipeLine`, `Rule`, `Makefile`, hard limits
- [x] `src/main.zig`: input file discovery, mode selection and the CLI options
- [x] Unit tests for the AST and the discovery

## Phase 2 — Context-sensitive lexer and dual-mode parser
Tracking: [ISSUE-002](.okfw/issues/issue-002-context-sensitive-lexer-and-dual-mode-parser--01a1d30ae694.md)
- [x] `src/lexer.zig`: continuations, comments, recipe lines (tab in legacy mode; tab or spaces in modern mode)
- [x] `src/parser.zig`: assignments, rules, pattern rules, `.PHONY`, `.DEFAULT_GOAL`, `@name:` and `task name:`
- [x] Unsupported directives fail with `file:line` ([ADR-0005](.okfw/decisions/adr-0005-unsupported-directives-fail-loudly--01a1d30ae687.md))
- [x] `tests/legacy_test.zig` and `tests/modern_test.zig`

## Phase 3 — Two-phase variable evaluator
Tracking: [ISSUE-003](.okfw/issues/issue-003-two-phase-variable-evaluator-and-target-classification--01a1d30ae69a.md)
- [x] `src/eval.zig`: immediate and deferred expansion with an explicit stack
- [x] Automatic variables `$@`, `$<`, `$^`, `$*`, `$?`, `$(@D)`, `$(@F)`
- [x] Functions `wildcard`, `shell`, `patsubst`, `subst`; substitution references; `$(MAKE)`
- [x] Target classifier for both modes ([ADR-0004](.okfw/decisions/adr-0004-modern-mode-declares-tasks-and-infers-phony-targets--01a1d30ae682.md))

## Phase 4 — Dependency graph and cycle detection
Tracking: [ISSUE-004](.okfw/issues/issue-004-dependency-graph-pattern-rules-and-cycle-detection--01a1d30ae6a0.md)
- [x] `src/dag.zig`: goal resolution through explicit rules, pattern rules and files
- [x] Three-color DFS on an explicit stack; the cycle error shows `file:line` for each rule
- [x] Topological order for the executor

## Phase 5 — Parallel executor and jobserver
Tracking: [ISSUE-005](.okfw/issues/issue-005-parallel-executor-and-gnu-make-jobserver--01a1d30ae6a7.md)
- [x] `src/executor.zig`: modification time checks, phony targets, the collision warning, recipe prefixes, `-n`
- [x] Parallel scheduler for `-jN`
- [x] `src/jobserver.zig`: pipe server and client (`R,W` and `fifo:PATH`)
- [x] `tests/acceptance.sh` with the three canonical scenarios below

## Phase 6 — Documentation site
Tracking: [ISSUE-006](.okfw/issues/issue-006-documentation-site-on-github-pages--01a1d33ebf0b.md)
- [x] Public repository `infrashift/zmake` with the Apache 2.0 license; the Pages source is GitHub Actions
- [x] `docs/`: Astro Starlight site with a landing page, guides, reference and project pages ([ADR-0009](.okfw/decisions/adr-0009-document-zmake-with-astro-starlight-on-github-pages--01a1d33eea33.md))
- [x] The logo moves to `docs/src/assets/zmake.jpeg`; Astro serves WebP copies
- [x] `make docs-demo`, `make docs-dev` and `make docs-build`
- [x] `scripts/ste-check.py` checks the docs pages
- [x] `.github/workflows/docs-release.yml` builds each pull request and deploys each push to `main`

## Phase 7 — Modern-mode ZMakefile for the zmake repo
Tracking: [ISSUE-008](.okfw/issues/issue-008-modern-mode-zmakefile-for-the-zmake-repo--01a1d348f8fb.md)
- [x] `ZMakefile` with every `Makefile` target as an `@name:` task ([ADR-0010](.okfw/decisions/adr-0010-keep-a-modern-mode-zmakefile-next-to-the-makefile--01a1d348f8d1.md))
- [x] Acceptance scenario 8 compares each `ZMakefile` dry run with GNU Make on the `Makefile`
- [x] Scenario 7 reads the `Makefile` with `-f Makefile`

## Acceptance scenarios
1. **The `build/` directory (modern mode).** Create `./build` and a `ZMakefile` with a `build:` rule. `zmake build` runs the recipe.
2. **Explicit task (modern mode).** Declare `@deploy: build` with 4-space indentation. `zmake deploy` runs `build`, then `deploy`.
3. **Strict legacy compatibility.** A `Makefile` with `.PHONY: clean`, `CC := gcc`, `%.o: %.c`, `$@` and `$<` compiles only dirty objects.

## Follow-ups
- `include`, conditionals, `define`, `export` and `vpath`
- Built-in implicit rules, built-in variables such as `CC`, suffix rules, double-colon rules and target-specific variables
- Functions other than `wildcard`, `shell`, `patsubst` and `subst`
- `-k` (keep going), `-q`, `-t` and `-B`
- Quoted values with spaces in `MAKEFLAGS` overrides
- Fix [ISSUE-007](.okfw/issues/issue-007-pattern-rules-drop-order-only-prerequisites--01a1d3419a7f.md): pattern rules drop their order-only prerequisites
- macOS and BSD support for the jobserver ([ADR-0002](.okfw/decisions/adr-0002-zig-0-17-1-standard-library-only-linux-first--01a1d30ae676.md))
