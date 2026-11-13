---
title: Make Targets
description: The Makefile targets that build, test, lint and document zmake.
---

The zmake repository has two input files with the same targets:

- `Makefile` is a plain GNU Make file. `make check` reads it.
- `ZMakefile` is the same file in modern mode. `zmake check` reads it, because zmake finds a `ZMakefile` first.

The `ZMakefile` declares each target as a task, with no `.PHONY` list:

```make
## check: run every gate
@check: lint test acceptance wiki docs-style

## lint: check the formatting and the Power of 10 rules
@lint:
    $(ZIG) fmt --check $(ZIG_SOURCES)
    $(PYTHON) -I scripts/nasa-lint.py
```

The acceptance suite compares the dry run of each target in both files. A
target that is missing from one file fails `make acceptance`.

| Target | Command |
|---|---|
| `make build` | `zig build` → `zig-out/bin/zmake` |
| `make test` | `zig build test`: the unit tests and the mode tests |
| `make lint` | `zig fmt --check` and `scripts/nasa-lint.py` (Power of 10) |
| `make fmt` | `zig fmt` on the Zig sources |
| `make acceptance` | `zig build acceptance`: end-to-end scenarios against the binary and GNU Make |
| `make cross` | Builds for macOS and FreeBSD on arm64 and x86_64 |
| `make wiki` | `okfw validate --all && okfw validate --okf` on the project wiki |
| `make docs-style` | `scripts/ste-check.py`: checks the documentation against ASD-STE100 rules |
| `make check` | All of the gates above |
| `make docs-demo` | Run zmake on `docs/src/demo/ZMakefile` and write the landing-page output |
| `make docs-dev` | Serve this site with live reload (bun) |
| `make docs-build` | Build this site into `docs/dist`, the same build as the Pages deploy |

Before a commit, run `make check` or `zmake check`. When you change the site, also run
`make docs-build`. Fix each failure and run the gates again until all pass.
