---
title: Contributing
description: The zmake development loop, the Power of 10 rules, the writing style and the project wiki.
---

## Requirements

- Zig 0.17.1
- GNU Make, for the acceptance comparison
- Python 3, for the lint scripts
- `okfw`, for the project wiki
- bun 1.3.9, for this site only

## The development loop

zmake works one phase at a time. `PLAN.md` holds the phases.

1. Read `PLAN.md`. Take the first unchecked phase and its wiki issue.
2. Implement only that phase. Use the Zig standard library only.
3. Run `make lint test`. Run `make acceptance` when the change touches the executor.
4. Fix each failure and run all gates again. Do not weaken or delete tests.
5. Record each decision as an ADR. File each bug as an issue in the wiki.
6. Update the pages of this site for the delivered features. Run `make docs-build`.
7. Run `make check`. All gates must pass.
8. Commit the code, the wiki and the docs together. Make one commit per phase.

See [Make Targets](../../reference/make-targets/) for each gate.

CI runs `make check` on Linux for each push and pull request. On macOS (arm64
and x86_64), it runs the unit tests, the acceptance suite and a smoke test of
the fifo jobserver. CI builds GNU Make 4.3 from source on macOS, because the
suite compares bytes with it. A FreeBSD VM runs the unit tests and the
acceptance suite. `tests/acceptance.sh` uses only commands that work on Linux,
macOS and FreeBSD.

## Power of 10

The code follows the NASA/JPL Power of 10 rules, adapted to Zig
([ADR-0003](../decisions/#adr-0003-adapt-the-nasa-power-of-10-rules-to-zig)):

- Do not use recursion. Use an explicit stack with a fixed limit.
- Give each loop a bound. A loop that reaches its bound returns an error.
- Keep each function at 60 lines or fewer.
- Write two or more `assert` calls per function on average.
- Do not add function pointers, vtables or factories.

`make lint` runs `scripts/nasa-lint.py`. A suppression needs a reason:
`// nasa-lint: allow(R4) <reason>`.

## Writing style

All documentation follows ASD-STE100 Simplified Technical English. This
includes this site, the wiki, `README.md` and `PLAN.md`.

- Use active voice and the simple present tense.
- Keep a descriptive sentence at 25 words or fewer, and a procedural step at 20 or fewer.
- Do not use words such as `should`, `will`, `just` or `simply`.

`make docs-style` runs `scripts/ste-check.py` on every page.

## The project wiki

The OKF wiki in `.okfw/` holds the architecture, the specs, the decisions and
the issues. Search it before you change a design: `okfw search "<query>"`.
Use `okfw move` and `okfw delete`, not `mv` and `rm`, so the links stay valid.
