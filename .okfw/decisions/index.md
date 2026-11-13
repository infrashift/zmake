# decisions

<!-- okfw:generated — maintained by okfw; edits here are overwritten -->

## Concepts

* [ADR-0001: Adopt an OKF wiki (okfw) for project knowledge](adr-0001-adopt-an-okf-wiki-okfw-for-project-knowledge--01a1d30ae670.md) - An okfw-managed OKF wiki in .okfw/ holds zmake project knowledge: architecture, specs, ADRs, issues and daily notes.
* [ADR-0002: Zig 0.17.1, standard library only, Linux first](adr-0002-zig-0-17-1-standard-library-only-linux-first--01a1d30ae676.md) - zmake targets Zig 0.17.1 with no dependencies outside the standard library, and supports Linux first.
* [ADR-0003: Adapt the NASA Power of 10 rules to Zig](adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md) - zmake follows the NASA/JPL Power of 10 rules where Zig and the problem allow; nasa-lint.py enforces the checkable rules.
* [ADR-0004: Modern mode declares tasks and infers phony targets](adr-0004-modern-mode-declares-tasks-and-infers-phony-targets--01a1d30ae682.md) - Modern mode removes .PHONY boilerplate with @name/task syntax and a bare-name heuristic, and runs a shadowed task with a warning.
* [ADR-0005: Unsupported directives fail loudly](adr-0005-unsupported-directives-fail-loudly--01a1d30ae687.md) - The parser rejects include, conditionals, define, export and vpath with a file:line error instead of a silent misparse.
* [ADR-0006: Expansion uses an explicit frame stack](adr-0006-expansion-uses-an-explicit-frame-stack--01a1d31ab339.md) - Variable and function expansion runs on a fixed-size frame stack instead of recursion, to satisfy Power of 10 rule R1.

