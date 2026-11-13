---
id: "01a1d381-05ef-768c-8b29-a252594267cd"
title: "ADR-0017: A double-colon target keeps one instance per rule"
type: "ADR"
tags:
  - "adr"
  - "dag"
  - "executor"
created: "2026-11-13T00:03:30-06:00"
timestamp: "2026-11-13T00:03:30-06:00"
description: "Each :: rule is an instance on its graph node; the executor decides and runs each due instance in file order in one job, and goals report when they finish."
---

# ADR-0017: A double-colon target keeps one instance per rule

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Phase 15, [ISSUE-015](/issues/issue-015-double-colon-rules--01a1d34ecd4a.md)

## Context
A target with `::` rules has one independent recipe for each rule. GNU Make runs a rule when the target is missing or when a prerequisite of that rule is newer. A rule with no prerequisites always runs. The rules run in file order. A target with both `:` and `::` rules is an error.

## Decision
- The parser reads `target:: prerequisites` as a rule with `double_colon` set. A double-colon pattern rule is an error.
- The graph keeps one `Instance` per double-colon rule on the node: prerequisites, recipes, line and file. The node has the prerequisites of all rules, so a target that needs it waits for all of them. `recipes` stays empty.
- `prepareDoubleColon` decides each instance with its own prerequisites against the time of the target before the job. The job runs the recipes of the instances that are due, in file order. A failed line stops the job, so the later rules do not run.
- `$^`, `$<` and `$?` give the prerequisites of each rule.
- Each command now carries its file, because the rules of one target can come from different files.
- The executor prints "is up to date" and "Nothing to be done" when a goal is done, not after all goals. GNU Make prints the message before it starts the next goal. The acceptance probe found this difference.

## Consequences
- Acceptance scenario 16 matches GNU Make 4.3 in six cases, also the error for mixed rules.
- `$(MAKE)` lines and `-n` work in double-colon recipes as in other recipes.

## Alternatives considered
- **One graph node per double-colon rule.** Rejected: the graph indexes nodes by target name, and each target that needs the file needs all of its rules.
