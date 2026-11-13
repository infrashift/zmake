# zmake

zmake is a Make-compatible build tool in Zig. It ships as one binary with no dependencies. It reads an input file in one of two syntax modes.

Documentation: https://infrashift.github.io/zmake/

| Mode | Input file | Behavior |
|---|---|---|
| Legacy | `Makefile`, `makefile`, `GNUmakefile` | Strict POSIX and GNU Make semantics. A target is a file unless `.PHONY` names it. Recipe lines start with a tab. |
| Modern | `ZMakefile`, `Make.zig.mk`, or `--modern` | No `.PHONY` boilerplate. `@name:` and `task name:` declare a task. Recipe lines start with a tab or with spaces. |

## Why modern mode
In GNU Make, a `build:` rule does nothing when a `build/` directory exists. The fix is a `.PHONY` list, and users forget it. Modern mode removes the problem:

```make
# ZMakefile
CC := gcc

build:
    $(CC) -o app main.c

@deploy: build
    ./deploy.sh app

app.tar: app
    tar -cf $@ app
```

- `build` is a bare name with no `$@` in its recipe. zmake infers a phony target. It runs the recipe also when `./build` exists, and prints a warning.
- `@deploy` is a task. It always runs, with no warning.
- `app.tar` has a dot and uses `$@`. It is a file target, so zmake compares modification times.

Modern mode still reads `.PHONY`, so Makefile snippets work with no change.

## Build
1. Install Zig 0.17.1.
2. Run `zig build --release` for a `ReleaseSafe` binary. Assertions stay active.
3. Copy `zig-out/bin/zmake` to a directory on your `PATH`.

## Usage
```text
zmake [options] [VAR=value ...] [target ...]

  -f FILE     Read FILE as the input file.
  -C DIR      Change to DIR before reading the input file.
  -j N        Run up to N jobs at the same time.
  -n          Print the recipe lines. Do not run them.
  -r          Do not use the built-in implicit rules.
  -R          Do not define the built-in variables. Implies -r.
  -k          Keep going: build the other targets after a failure.
  -q          Run nothing. Exit 0 when the goals are up to date, else 1.
  -t          Touch the out-of-date targets. Do not run their recipes.
  -B          Treat every target as out of date.
  -s          Do not echo the recipe lines.
  --jobserver-style=fifo|pipe
              The style of a new jobserver. Default: pipe on Linux, fifo elsewhere.
  --modern    Use modern mode for any input file.
  --legacy    Use legacy mode for any input file.
```

zmake serves and joins the GNU Make jobserver. A recursive `$(MAKE)` and a parent GNU Make share one pool of jobs. zmake builds for Linux, macOS and FreeBSD.

## Compatibility
zmake supports these GNU Make features:

- The assignments `=`, `:=`, `::=`, `?=` and `+=`, and command-line overrides
- Explicit rules, pattern rules, double-colon rules, order-only prerequisites and inline `; recipe` text
- Target-specific and pattern-specific variables, with `override`, `export` and `private`
- The built-in variables and implicit rules of GNU Make, suffix rules, `-r` and `-R`
- The automatic variables `$@`, `$<`, `$^`, `$+`, `$*`, `$?` and their `D` and `F` forms
- The GNU Make functions, for example `foreach`, `call`, `if`, `filter` and `file`, and substitution references
- `.PHONY`, `.DEFAULT_GOAL`, `.PRECIOUS`, `.SILENT`, `.NOTPARALLEL`, `.DELETE_ON_ERROR` and `.EXPORT_ALL_VARIABLES`
- The conditionals `ifeq`, `ifneq`, `ifdef` and `ifndef`, and `define`, `override`, `undefine`, `$(eval ...)`, `include`, `export`, `unexport` and `vpath`

zmake stops with an error for features outside this list, for example `load`, `.ONESHELL` or `$(guile ...)`. It does not misread them in silence. See `PLAN.md` for the follow-ups.

## Development
Run `make check` or `zmake check`. GNU Make reads the `Makefile`. zmake reads the `ZMakefile`, which has the same targets in modern mode. The gates are:

- `make lint`: `zig fmt --check` and `scripts/nasa-lint.py`, which checks the NASA Power of 10 rules
- `make test`: the unit tests and the mode tests
- `make acceptance`: the end-to-end scenarios, with a comparison against GNU Make
- `make cross`: builds for macOS and FreeBSD on arm64 and x86_64
- `make wiki`: validation of the OKF wiki in `.okfw/`
- `make docs-style`: an ASD-STE100 check of the documentation

CI runs `make check` on Linux, and the unit tests and a jobserver smoke test on macOS (arm64 and x86_64).

The wiki in `.okfw/` holds the architecture, the specs and the design decisions. Start with the *zmake architecture overview*.

## License
Apache License 2.0. See [LICENSE](LICENSE).
