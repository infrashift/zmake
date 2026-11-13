---
id: "01a1d327-df21-7e4b-b46d-97fe3c739895"
title: "ADR-0007: Delete partial targets by mode"
type: "ADR"
tags:
  - "adr"
  - "executor"
  - "compatibility"
created: "2026-11-12T22:26:08-06:00"
timestamp: "2026-11-12T22:26:08-06:00"
description: "Legacy mode deletes a failed file target only with .DELETE_ON_ERROR, as GNU Make does; modern mode deletes it by default."
---

# ADR-0007: Delete partial targets by mode

**Status:** Accepted
**Date:** 2026-11-12
**Source:** Phase 5. A check against GNU Make 4.3 corrected the plan.

## Context
The plan said that zmake deletes a partial file target after a failed recipe line, "as GNU does". GNU Make does this only when the input file declares `.DELETE_ON_ERROR`. Without it, GNU Make keeps the partial file. The next run then sees an up-to-date target with bad content.

## Decision
- **Legacy mode:** follow GNU Make. Delete the target only with `.DELETE_ON_ERROR`.
- **Modern mode:** delete the target by default. This matches the goal of modern mode: remove the GNU Make defaults that fail in silence.
- In both modes, zmake deletes only a `file` target that the recipe changed. It keeps `.PRECIOUS` and `.SECONDARY` targets. It deletes nothing under `-n`.
- The message is the GNU form: `zmake: *** Deleting file 'out'`.

## Consequences
- Legacy builds behave as GNU Make builds do.
- A modern input file that needs the partial file for debugging lists it in `.PRECIOUS`.

## Alternatives considered
- **Delete in both modes.** Rejected: legacy mode promises strict GNU semantics.
- **Delete in neither mode.** Rejected: modern mode keeps a known trap.

Related: [Syntax modes and target kinds](/specs/syntax-modes-and-target-kinds--01a1d30ae660.md)
