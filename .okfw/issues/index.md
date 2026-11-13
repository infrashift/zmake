# issues

<!-- okfw:generated — maintained by okfw; edits here are overwritten -->

## Concepts

* [ISSUE-001: Scaffolding, AST and input file discovery](issue-001-scaffolding-ast-and-input-file-discovery--01a1d30ae68d.md) - Phase 1: build.zig, the AST types, input file discovery, mode selection and the CLI options.
* [ISSUE-002: Context-sensitive lexer and dual-mode parser](issue-002-context-sensitive-lexer-and-dual-mode-parser--01a1d30ae694.md) - Phase 2: logical lines, recipe detection per mode, assignments, rules, pattern rules, special targets and task syntax.
* [ISSUE-003: Two-phase variable evaluator and target classification](issue-003-two-phase-variable-evaluator-and-target-classification--01a1d30ae69a.md) - Phase 3: variable flavors, immediate and deferred expansion, automatic variables, functions and the target kind classifier.
* [ISSUE-004: Dependency graph, pattern rules and cycle detection](issue-004-dependency-graph-pattern-rules-and-cycle-detection--01a1d30ae6a0.md) - Phase 4: goal resolution through explicit rules, pattern rules and files, cycle detection with line numbers, topological order.
* [ISSUE-005: Parallel executor and GNU Make jobserver](issue-005-parallel-executor-and-gnu-make-jobserver--01a1d30ae6a7.md) - Phase 5: out-of-date checks, recipe execution, -j scheduling, the jobserver, and the acceptance scenarios.
* [ISSUE-006: Documentation site on GitHub Pages](issue-006-documentation-site-on-github-pages--01a1d33ebf0b.md) - Phase 6: an Astro Starlight site in docs/, published to GitHub Pages through GitHub Actions.
* [ISSUE-007: Pattern rules drop order-only prerequisites](issue-007-pattern-rules-drop-order-only-prerequisites--01a1d3419a7f.md) - A pattern rule loses its order-only prerequisites, so obj/%.o: src/%.c | obj never creates obj/.

