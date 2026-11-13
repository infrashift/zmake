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
* [ISSUE-008: Modern-mode ZMakefile for the zmake repo](issue-008-modern-mode-zmakefile-for-the-zmake-repo--01a1d348f8fb.md) - Phase 7: a ZMakefile with the same targets as the Makefile, checked against GNU Make by the acceptance suite.
* [ISSUE-009: Text, control and file functions](issue-009-text-control-and-file-functions--01a1d34ecd22.md) - Phase 9: the GNU Make functions beyond subst, patsubst, wildcard and shell, on the frame stack without recursion.
* [ISSUE-010: Conditionals, define, override, undefine and eval](issue-010-conditionals-define-override-undefine-and-eval--01a1d34ecd29.md) - Phase 10: a reader that evaluates conditionals and multi-line definitions while it reads the input file.
* [ISSUE-011: include and MAKEFILE_LIST](issue-011-include-and-makefile-list--01a1d34ecd30.md) - Phase 11: include, -include and sinclude, with an explicit include stack, and MAKEFILE_LIST.
* [ISSUE-012: export and unexport](issue-012-export-and-unexport--01a1d34ecd36.md) - Phase 12: export and unexport control the environment of each recipe line.
* [ISSUE-013: vpath and VPATH](issue-013-vpath-and-vpath--01a1d34ecd3c.md) - Phase 13: directory search for prerequisites through VPATH and the vpath directive.
* [ISSUE-014: Target-specific and pattern-specific variables](issue-014-target-specific-and-pattern-specific-variables--01a1d34ecd43.md) - Phase 14: target-specific and pattern-specific variables, inherited by prerequisites.
* [ISSUE-015: Double-colon rules](issue-015-double-colon-rules--01a1d34ecd4a.md) - Phase 15: double-colon rules, each with an independent recipe.
* [ISSUE-016: Built-in variables, implicit rules and suffix rules](issue-016-built-in-variables-implicit-rules-and-suffix-rules--01a1d34ecd51.md) - Phase 16: the GNU Make built-in variables and implicit rules, old-style suffix rules, and -r / -R.
* [ISSUE-017: The options -k, -q, -t and -B](issue-017-the-options-k-q-t-and-b--01a1d34ecd58.md) - Phase 17: keep going, question, touch and always-make, and combined short options.
* [ISSUE-018: Quoted values in MAKEFLAGS](issue-018-quoted-values-in-makeflags--01a1d34ecd5f.md) - Phase 18: command-line variables with spaces survive the trip through MAKEFLAGS.
* [ISSUE-019: Jobserver on macOS and the BSDs](issue-019-jobserver-on-macos-and-the-bsds--01a1d34ecd67.md) - Phase 19: the jobserver and the build without Linux-only system calls.
* [ISSUE-020: Static pattern rules](issue-020-static-pattern-rules--01a1d399e029.md) - Static pattern rules (objs: %.o: %.c) give one explicit rule per target; today zmake stops with a clear error.
* [ISSUE-021: Acceptance suite on macOS](issue-021-acceptance-suite-on-macos--01a1d4dbc5ce.md) - CI builds GNU Make 4.3 on macOS and runs the acceptance suite there; the script uses only portable commands.
* [ISSUE-022: Test runs on FreeBSD](issue-022-test-runs-on-freebsd--01a1d4ee3b4d.md) - A CI job runs the unit tests and the acceptance suite in a FreeBSD VM, with pinned downloads and a pinned VM action.

