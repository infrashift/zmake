---
id: "01a1d30a-e654-7a1b-be44-47d87ee7f040"
title: "Development workflow"
type: "Guide"
tags:
  - "conventions"
  - "workflow"
  - "meta"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "The loop for each zmake phase: implement, lint, verify until green, update the wiki, then commit."
---

# Development workflow

Every change follows this loop. Do not report or commit work while a gate fails.

1. **Pick the phase.** Read `PLAN.md`. Take the first unchecked phase. Find its mirror issue with `okfw search --path issues --tag open`.
2. **Tag the issue.** Run `okfw remove-tags <id> open && okfw add-tags <id> in-progress`.
3. **Implement only that phase.** Use the Zig standard library only. Keep `src/main.zig` a thin entry point.
4. **Apply the Power of 10 rules.** Read [ADR-0003](/decisions/adr-0003-adapt-the-nasa-power-of-10-rules-to-zig--01a1d30ae67c.md). Use explicit bounded stacks, not recursion.
5. **Lint and verify.** Run `make lint test`. Run `make acceptance` when the executor exists.
6. **Repeat until green.** Fix each failure and run all gates again. Do not weaken or delete tests.
7. **Update the wiki during the work.** Record each decision as an ADR when you make it. File each bug or design debt as an issue.
8. **Close the phase.** Tick the `PLAN.md` checkboxes and the acceptance criteria. Add a **Resolution** section. Swap the tag `in-progress` → `closed`.
9. **Check the writing style.** Run `make docs-style`. Fix every error.
10. **Validate the wiki.** Run `make wiki`.
11. **Journal.** Add an entry to today's `okfw daily` note: what changed, what you learned, what is next.
12. **Commit.** Commit the code and the wiki together. Make one commit per phase.

See [Wiki conventions](/wiki-conventions--01a1d30ae64f.md).
