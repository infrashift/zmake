# CLAUDE.md — zmake

## Purpose (WHY)
zmake is a Make-compatible build tool in Zig. It ships as one static binary. It reads an input file in one of two syntax modes:

- **Legacy mode** (`Makefile`, `makefile`, `GNUmakefile`): strict POSIX and GNU Make semantics. A target is a file unless `.PHONY` names it. Recipe lines start with a tab.
- **Modern mode** (`ZMakefile`, `Make.zig.mk`, `--modern`): no `.PHONY` boilerplate. `@name:` and `task name:` declare a task. zmake infers a phony target from a bare name. Recipe lines start with a tab or with spaces.

## Tech Stack (WHAT)
- **Language:** Zig 0.17.1, pinned in `build.zig.zon` as `minimum_zig_version`. The toolchain lives in `~/.local/zig/`.
- **Dependencies:** the Zig standard library only. Write an ADR before you add a dependency.
- **Platform:** Linux, macOS and FreeBSD. The tests run on Linux; `make cross` builds the other systems. The jobserver uses a pipe on Linux and a named fifo elsewhere ([ADR-0020](.okfw/decisions/adr-0020-a-named-fifo-shares-the-jobserver-off-linux--01a1d399e000.md)).
- **Wiki:** okfw (`.okfw/`). See the okfw block below.
- **Docs:** Astro Starlight in `docs/` (bun 1.3.9), deployed to GitHub Pages ([ADR-0009](.okfw/decisions/adr-0009-document-zmake-with-astro-starlight-on-github-pages--01a1d33eea33.md)).

## Layout
- `src/main.zig` is a thin CLI entry point.
- `src/root.zig` exports the library modules for the tests.
- `src/` holds the modules: `ast`, `lexer`, `parser`, `eval`, `dag`, `executor`, `jobserver`.
- `tests/` holds the mode tests (`legacy_test.zig`, `modern_test.zig`) and `acceptance.sh`.
- `docs/` holds the Astro Starlight site. `docs/src/content/docs/docs/` holds the pages. `docs/src/assets/` holds the logo.
- `.github/workflows/docs-release.yml` deploys the site to https://infrashift.github.io/zmake/.
- `scripts/` holds the lint scripts: `nasa-lint.py` (Power of 10) and `ste-check.py` (ASD-STE100).

## Verification & Workflow Commands (HOW)
`Makefile` (GNU Make) and `ZMakefile` (zmake, modern mode) have the same targets. Change both together: acceptance scenario 8 compares them ([ADR-0010](.okfw/decisions/adr-0010-keep-a-modern-mode-zmakefile-next-to-the-makefile--01a1d348f8d1.md)).

Run these targets after every change:
- `make lint` → `zig fmt --check` and `scripts/nasa-lint.py`
- `make test` → `zig build test`
- `make build` → `zig build`
- `make acceptance` → `zig build acceptance` (end-to-end scenarios against the binary)
- `make cross` → build for macOS and FreeBSD on arm64 and x86_64
- `make wiki` → `okfw validate --all && okfw validate --okf`
- `make docs-style` → `scripts/ste-check.py`
- `make check` → all of the gates above
- `make docs-build` → build the Starlight site (the same build as the Pages deploy)
- `make docs-dev` → serve the site locally; `make docs-demo` → regenerate the landing-page demo output

## Mandatory Execution Rules
1. **One phase at a time.** Read `PLAN.md`. Implement only the first unchecked phase. Follow the *Development workflow* guide in `.okfw/`.
2. **Repeat until green.** Implement, lint, verify. Fix each failure and run all gates again. Do not commit while a gate fails.
3. **Test integrity.** Do not weaken or delete tests to make a gate pass.
4. **Power of 10.** Follow the NASA/JPL Power of 10 rules as ADR-0003 adapts them to Zig. `make lint` enforces the rules that a script can check.
5. **Minimal abstractions.** Add no unrequested interfaces, vtables or factories.
6. **Wiki stays in sync.** Each `PLAN.md` phase has a mirror issue in `.okfw/issues/`. Record each decision as an ADR when you make it. Close the issue when the phase is done.
7. **Documentation follows ASD-STE100 (Simplified Technical English).** Use active voice, simple present tense and short sentences. Run `make docs-style`.

<!-- BEGIN okfw -->
## Project knowledge base (okfw)

zmake keeps a local-first OKF wiki in `.okfw/`: markdown concepts with
YAML frontmatter, linked to each other. The files are the whole database —
search and the link graph are computed from them on demand, so there is no
index to build and nothing to sync. Each directory's `index.md` is generated
and gives a cheap overview before you open anything (OKF section 8).

- **Search before you derive.** `okfw search "<query>"` / `okfw_search`. The
  wiki holds what the code does not say — why things are built the way they
  are, what was considered and rejected, dependency and security findings,
  operational context, open work. Check it before explaining a design,
  assessing risk, or running an analysis someone may already have recorded and
  adjudicated.
- **Browse top-down.** Each directory's `index.md` lists its concepts with
  their descriptions (`okfw_read {"ref":"<dir>/"}` over MCP). Open only what fits.
- **Search before you write**, too, so a new concept links to what already
  exists instead of duplicating it.
- **Link actively** — `[Title](/dir/file.md)` from the wiki root, or
  `./file.md`. Links are what makes the wiki more than a folder.
- **One idea per concept**, with a one-sentence `description`.
- **Use `okfw move` / `okfw delete`, never `mv` / `rm`.** `move` repairs every
  link to the concept and its own relative links, and both keep the `index.md`
  listings current; the shell commands break the links and leave the listings
  stale.
- **`status` is the OKF lifecycle field** (`draft`/`stable`/`deprecated`), not
  task state. Mark superseded knowledge rather than deleting it.
- **Custom metadata goes under `x:`** — the schema is closed and rejects any
  other unrecognized key.
- Don't edit `index.md` or `log.md`; okfw generates them.

Results are capped and say so: `truncated`, or `… N more`, means you did not
see everything — raise the limit or page with `--offset`/`"offset"`.

`okfw mcp` serves all of this as MCP stdio tools named `okfw_*`.
<!-- END okfw -->
