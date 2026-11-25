# Changelog

Each release has a section with the version as its heading. The release
workflow copies the section into the notes of the GitHub release.

## 0.2.0

zmake 0.2.0 adds Windows on x86_64. Windows support is new and experimental.

### Downloads

| Archive | System |
|---|---|
| `zmake-v0.2.0-linux-amd64.tar.gz` | Linux on x86_64. A static binary with no libc. |
| `zmake-v0.2.0-linux-arm64.tar.gz` | Linux on arm64. A static binary with no libc. |
| `zmake-v0.2.0-macos-arm64.tar.gz` | macOS on Apple silicon. An ad-hoc signature, no notarization. |
| `zmake-v0.2.0-windows-amd64.zip` | Windows on x86_64. New and experimental. |

Each tar archive holds `bin/zmake`, the man pages `zmake(1)` and
`zmakefile(5)` under `share/man`, `LICENSE` and `README.md`. The zip archive
holds `bin/zmake.exe` and the same files. `SHA256SUMS` gives the checksum of
each archive. Each archive also has a build-provenance attestation:

```sh
gh attestation verify zmake-v0.2.0-linux-amd64.tar.gz --repo infrashift/zmake
```

### Windows on x86_64 (new, experimental)

zmake builds and runs on Windows on x86_64. Windows support is new and
experimental. CI runs the unit tests and a smoke test on Windows, but not the
acceptance suite. A later release can change the Windows behavior. See
[Windows (Experimental)](https://infrashift.github.io/zmake/docs/guides/windows/) ([ADR-0029](https://infrashift.github.io/zmake/docs/project/decisions/#adr-0029-zmake-runs-on-windows-x86_64-with-shexe-and-a-semaphore-jobserver)).

- Each recipe line runs in `sh.exe -c`. Windows finds `sh.exe` through `PATH`, for example the one of Git for Windows or MSYS2.
- `\` also separates the parts of a name. `C:/` and `C:\` start an absolute name. A rule can name `C:/out/app.exe` as a target. `;` separates the directories of `VPATH` and `vpath`.
- zmake gives the shell names with `/`: `$(MAKE)`, `$(abspath ...)`, `$(realpath ...)` and the working directory.
- A new jobserver pool is a named semaphore, as in GNU Make for Windows. `--jobserver-style=sem` selects it.
- zmake compares the exact case of file names, as on macOS.
- The release has a `windows-amd64` zip archive with `bin/zmake.exe`.

## 0.1.0

The first release of zmake. zmake is a Make-compatible build tool in one
static binary.

### Downloads

| Archive | System |
|---|---|
| `zmake-v0.1.0-linux-amd64.tar.gz` | Linux on x86_64. A static binary with no libc. |
| `zmake-v0.1.0-linux-arm64.tar.gz` | Linux on arm64. A static binary with no libc. |
| `zmake-v0.1.0-macos-arm64.tar.gz` | macOS on Apple silicon. An ad-hoc signature, no notarization. |

Each archive holds `bin/zmake`, the man pages `zmake(1)` and `zmakefile(5)`
under `share/man`, `LICENSE` and `README.md`. `SHA256SUMS` gives the checksum
of each archive. Each archive also has a build-provenance attestation:

```sh
gh attestation verify zmake-v0.1.0-linux-amd64.tar.gz --repo infrashift/zmake
```

On FreeBSD and on macOS on x86_64, build zmake from source with Zig 0.17.1.
See [Getting Started](https://infrashift.github.io/zmake/docs/getting-started/).

### Two syntax modes

- **Legacy mode** reads `Makefile`, `makefile` and `GNUmakefile` with POSIX and GNU Make semantics.
- **Modern mode** reads `ZMakefile` and `Make.zig.mk`, or any file with `--modern`.
  - `@name:` and `task name:` declare a task.
  - zmake infers a phony target from a bare name.
  - A recipe line starts with a tab or with spaces.

### GNU Make features

- Immediate and deferred variables, all assignment operators, `override`, `export`, `unexport`, `undefine` and `define`.
- Conditionals, `include`, `-include`, `sinclude` and `MAKEFILE_LIST`.
- The text, file name, conditional, loop, variable and message functions, and `$(eval ...)`.
- Pattern rules, static pattern rules, double-colon rules, suffix rules and the built-in implicit rules.
- Target-specific and pattern-specific variables, with `private`.
- `VPATH` and `vpath`, and order-only prerequisites.
- The options `-f`, `-C`, `-j`, `-n`, `-r`, `-R`, `-k`, `-q`, `-t`, `-B` and `-s`. They go to sub-makes through `MAKEFLAGS`.

### Parallel builds

`-jN` runs up to N jobs. zmake shares jobs with GNU Make through the
jobserver: a pipe on Linux, and a named fifo on macOS and FreeBSD.

### Not in this release

`$(guile ...)`, `.ONESHELL`, `.SECONDEXPANSION`, `--output-sync`, and the
remake of included makefiles.
