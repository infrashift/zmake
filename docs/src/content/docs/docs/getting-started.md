---
title: Getting Started
description: Install a zmake release or build zmake from source, then run a ZMakefile and an existing Makefile.
---

zmake has release archives for Linux on x86_64 and arm64, and for macOS on
Apple silicon. On other systems, build zmake from source. CI tests zmake on
Linux, macOS and FreeBSD.

## Install a release

1. Find your archive on the [releases page](https://github.com/infrashift/zmake/releases): `linux-amd64`, `linux-arm64` or `macos-arm64`.
2. Download the archive and `SHA256SUMS`.
3. Check the archive.
4. Unpack the archive and copy `bin` and `share` to `~/.local`.
5. Put `~/.local/bin` on your `PATH`.

For example, on Linux on x86_64:

```sh
v=0.1.0
a=zmake-v$v-linux-amd64
curl -fsSLO https://github.com/infrashift/zmake/releases/download/v$v/$a.tar.gz
curl -fsSLO https://github.com/infrashift/zmake/releases/download/v$v/SHA256SUMS
shasum -a 256 -c SHA256SUMS --ignore-missing
tar -xzf $a.tar.gz
mkdir -p ~/.local
cp -R $a/bin $a/share ~/.local/
```

The GitHub CLI also checks where the archive comes from. The attestation
names the workflow run that built the archive:

```sh
gh attestation verify $a.tar.gz --repo infrashift/zmake
```

The Linux binaries are static. They need no libc.

:::note[macOS]
The macOS binary has an ad-hoc signature. It has no Developer ID signature and
no notarization. `curl` does not add the quarantine flag, so the steps above
work. When you download the archive with a browser, macOS stops the binary.
Remove the flag before you copy the binary:

```sh
xattr -d com.apple.quarantine $a/bin/zmake
```
:::

## Build from source

1. Install Zig 0.17.1 from [ziglang.org](https://ziglang.org/download/).
2. Clone the repository: `git clone https://github.com/infrashift/zmake`.
3. In the `zmake` directory, run `zig build --release -p ~/.local`.
4. Put `~/.local/bin` on your `PATH`.

`zig build --release` makes a `ReleaseSafe` binary. The assertions and the Zig
safety checks stay active in the shipped binary.

`-p ~/.local` installs the binary in `~/.local/bin` and the man pages in
`~/.local/share/man`. `man` finds the pages with no change to `MANPATH`. See
[Manual Pages](../reference/man-pages/).

Check the binary and the man page:

```sh
zmake --help
man zmake
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

zmake reads conditionals, `include`, `define`, `vpath` and the GNU Make
functions. It stops with an error when the `Makefile` uses a feature outside
its scope, for example `.ONESHELL`:

```text
Makefile:4: *** special target '.ONESHELL' is not supported.  Stop.
```

See [Compatibility](../reference/compatibility/) for the full list.

## Next steps

- [Syntax Modes](../guides/syntax-modes/): how zmake selects the mode.
- [Tasks and Phony Inference](../guides/tasks-and-phony-inference/): the modern-mode rules.
- [CLI](../reference/cli/): every option and exit code.
- [Manual Pages](../reference/man-pages/): `man zmake` and `man 5 zmakefile`.
