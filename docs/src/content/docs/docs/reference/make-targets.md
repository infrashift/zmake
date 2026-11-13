---
title: Make Targets
description: The Makefile targets that build, test, lint and document zmake.
---

The zmake repository uses a plain GNU Make `Makefile`. zmake can also run it:
`zmake check` gives the same result as `make check`.

| Target | Command |
|---|---|
| `make build` | `zig build` → `zig-out/bin/zmake` |
| `make test` | `zig build test`: the unit tests and the mode tests |
| `make lint` | `zig fmt --check` and `scripts/nasa-lint.py` (Power of 10) |
| `make fmt` | `zig fmt` on the Zig sources |
| `make acceptance` | `zig build acceptance`: end-to-end scenarios against the binary and GNU Make |
| `make wiki` | `okfw validate --all && okfw validate --okf` on the project wiki |
| `make docs-style` | `scripts/ste-check.py`: checks the documentation against ASD-STE100 rules |
| `make check` | All of the gates above |
| `make docs-demo` | Run zmake on `docs/src/demo/ZMakefile` and write the landing-page output |
| `make docs-dev` | Serve this site with live reload (bun) |
| `make docs-build` | Build this site into `docs/dist`, the same build as the Pages deploy |

Before a commit, run `make check`. When you change the site, also run
`make docs-build`. Fix each failure and run the gates again until all pass.
