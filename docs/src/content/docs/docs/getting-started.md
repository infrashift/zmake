---
title: Getting Started
description: Build zmake from source with Zig 0.17.1, then run a ZMakefile and an existing Makefile.
---

zmake has no binary release yet. Build it from source. zmake builds for Linux,
macOS and FreeBSD. CI tests it on Linux and macOS.

## Build from source

1. Install Zig 0.17.1 from [ziglang.org](https://ziglang.org/download/).
2. Clone the repository: `git clone https://github.com/infrashift/zmake`.
3. In the `zmake` directory, run `zig build --release`.
4. Copy `zig-out/bin/zmake` to a directory on your `PATH`.

`zig build --release` makes a `ReleaseSafe` binary. The assertions and the Zig
safety checks stay active in the shipped binary.

Check the binary:

```sh
zmake --help
```

## Your first ZMakefile

Create a file with the name `ZMakefile`. The name selects modern mode.

```make
# ZMakefile
GREETING := hello

build:
    @echo "$(GREETING) from build"

@deploy: build
    @echo "deploy runs after build"
```

Run the `deploy` task:

```sh
zmake deploy
```

```text
hello from build
deploy runs after build
```

- The recipe lines start with four spaces. Modern mode accepts a tab or spaces.
- `build` has no `.PHONY` entry. zmake infers a phony target, because `build` is a bare name and its recipe does not refer to `$@`.
- `@deploy` is a task. It always runs.

Now create a `build/` directory and run `zmake build`. GNU Make prints
`'build' is up to date` in this case. zmake runs the recipe and prints a warning:

```text
zmake: warning: target 'build' shadows existing path './build'; prefix with '@build:' to silence
hello from build
```

## Run an existing Makefile

zmake reads a `Makefile` in legacy mode, with GNU Make semantics:

```sh
zmake -C path/to/project -j8
```

zmake stops with an error when the `Makefile` uses a feature outside its scope,
for example `include` or `ifeq`:

```text
Makefile:7: *** unsupported directive 'ifeq'.  Stop.
```

See [Compatibility](../reference/compatibility/) for the full list.

## Next steps

- [Syntax Modes](../guides/syntax-modes/): how zmake selects the mode.
- [Tasks and Phony Inference](../guides/tasks-and-phony-inference/): the modern-mode rules.
- [CLI](../reference/cli/): every option and exit code.
