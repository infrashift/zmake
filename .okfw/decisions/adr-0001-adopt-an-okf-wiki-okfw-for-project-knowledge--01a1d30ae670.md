---
id: "01a1d30a-e670-7b4a-a39c-67453ab63665"
title: "ADR-0001: Adopt an OKF wiki (okfw) for project knowledge"
type: "ADR"
tags:
  - "adr"
  - "process"
  - "okf"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "An okfw-managed OKF wiki in .okfw/ holds zmake project knowledge: architecture, specs, ADRs, issues and daily notes."
---

# ADR-0001: Adopt an OKF wiki (okfw) for project knowledge

**Status:** Accepted
**Date:** 2026-11-12
**Source:** User request, `CLAUDE.md`

## Context
zmake makes several decisions that differ from GNU Make: two syntax modes, phony inference and the Power of 10 rules. Chat history and commit messages hide the reasons for these decisions. Sibling infrashift repos (`whac-a-leak`, `vizzini-pr-reviewer`, `cuix`) use okfw.

## Decision
- An OKF wiki lives at `.okfw/` in the repo root. The `okfw` CLI manages it. The repository includes it.
- `okfw install --platform claude` adds the Claude Code skill and the managed `CLAUDE.md` block. The `.mcp.json` file registers `okfw mcp`.
- `PLAN.md` stays the phase checklist. Each phase has a mirror issue in `issues/`.
- Conventions: [Wiki conventions](/wiki-conventions--01a1d30ae64f.md). Loop: [Development workflow](/development-workflow--01a1d30ae654.md).

## Consequences
- `okfw search` finds decisions and open work. Links connect them into a graph.
- `PLAN.md` and the issues can drift apart. The workflow guide requires an update to both.

## Alternatives considered
- **Plain `docs/` markdown.** Rejected: no frontmatter, no typed search and no generated indexes.
