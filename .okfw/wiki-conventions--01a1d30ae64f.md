---
id: "01a1d30a-e64f-7458-a21f-94b58674e06c"
title: "Wiki conventions"
type: "Guide"
tags:
  - "conventions"
  - "meta"
created: "2026-11-12T21:54:29-06:00"
timestamp: "2026-11-12T21:54:29-06:00"
description: "Layout, writing style and authoring rules for architecture notes, specs, ADRs, issues and daily notes in this wiki."
---

# Wiki conventions

# Wiki conventions

This guide defines how the zmake OKF wiki (`.okfw/`) stores project knowledge.

- Create concepts with `okfw create` or the okfw MCP `create` tool. Do not write frontmatter by hand.
- Search before you write. Link to related concepts.
- Keep one idea per concept. Give each concept a one-sentence `description`.

## Layout
| Path | Type | Contents |
|---|---|---|
| `architecture/` | `Architecture` | System overview, module boundaries, data flow. |
| `specs/` | `Spec` | Contracts: syntax modes, target kinds, CLI, jobserver. The spec states intent. The code implements it. |
| `decisions/` | `ADR` | Architecture decision records. |
| `issues/` | `Issue` (kind `issue`) | Tracked work: one issue per `PLAN.md` phase, plus bugs and design debt. |
| `daily/` | daily note | `okfw daily`: what changed, what you learned, what is next. |

## PLAN.md and issues
`PLAN.md` is the phase checklist. Each phase has a mirror issue (ISSUE-001 … ISSUE-005). Each phase heading in `PLAN.md` has a `Tracking:` line that links to its issue. When a phase is done, tick the `PLAN.md` checkboxes and the acceptance criteria of the issue.

## ADRs (`decisions/`)
- Title: `ADR-NNNN: <decision>`. Number ADRs in sequence. Do not reuse a number.
- Command: `okfw create "ADR-NNNN: <title>" --path decisions --type ADR --tags adr,<topic> -d "<one sentence>" --body "<markdown>"`
- Body: **Status** (Proposed / Accepted / Superseded by ADR-XXXX), **Date**, **Source**, then **Context**, **Decision**, **Consequences**, **Alternatives considered**.
- To supersede an ADR, write the new ADR with a link to the old ADR. Update the Status line of the old ADR. Run `okfw set-lifecycle <id> deprecated`.
- Write an ADR before you add a dependency outside the Zig standard library.

## Issues (`issues/`)
- Title: `ISSUE-NNN: <summary>`. Number issues in sequence.
- Command: `okfw create "ISSUE-NNN: <title>" --kind issue --path issues --type Issue --tags issue,open,phase-<n>,<area> -d "<summary>" --body "<markdown>"`
- Body: a **Status/Phase** line, **Description**, **Acceptance Criteria** (checkboxes), **Notes**, **Related**.
- okfw has no status field for issues. Tags carry the state: `open` → `in-progress` → `closed`. Use `okfw remove-tags` and `okfw add-tags`. Keep the Status line the same as the tags. Add a **Resolution** section when you close an issue.
- Find open work with `okfw search --path issues --tag open`.

## Writing style
All documentation follows ASD-STE100 Simplified Technical English. This includes the wiki, `README.md`, `PLAN.md` and `CLAUDE.md`.

- Use active voice and simple present tense: "The parser rejects the line."
- Start each procedural step with an imperative verb: Run, Read, Inspect, Verify, Add, Set.
- Keep procedural steps to 20 words or fewer. Keep descriptive sentences to 25 words or fewer.
- Use a verb, not a noun form: "The evaluator expands the variable", not "Expansion of the variable occurs".
- Use one term for one concept. This wiki uses these terms:
  - *input file*: the file that zmake reads, for example `Makefile` or `ZMakefile`.
  - *legacy mode* and *modern mode*: the two syntax modes.
  - *rule*, *target*, *prerequisite*, *recipe*, *recipe line*, *pattern rule*, *stem*.
  - *file target* and *phony target*. A *task* is a phony target that `@name:` or `task name:` declares in modern mode.
  - *variable*, *automatic variable* and *function* (a built-in Make function, for example `wildcard`).
  - *job*, *token*, *jobserver* and *phase* (one unit of work in `PLAN.md`).
- Do not use the words `should`, `will`, `would`, `please`, `simply`, `just`, `very`, `really` or `easily`. Do not use marketing language.
- Run `make docs-style`. The check (`scripts/ste-check.py`) reports banned words and long sentences as errors. It reports possible passive voice as warnings.

## Housekeeping
- Use `okfw move` and `okfw delete`. Do not use `mv` or `rm`. The okfw commands repair links and update the `index.md` listings.
- `status` is the OKF lifecycle field (`draft` / `stable` / `deprecated`). It is not the task state. Mark superseded knowledge `deprecated`. Do not delete it.
- Do not edit `index.md` or `log.md`. okfw generates them.
- Run `make wiki` before you commit wiki changes.

See [Development workflow](/development-workflow--01a1d30ae654.md).
