---
title: Manual Pages
description: The zmake(1) and zmakefile(5) man pages, where zig build installs them, and how man finds them on Linux, macOS and FreeBSD.
---

zmake has two man pages:

| Page | Content |
|---|---|
| `zmake(1)` | The command line: options, input file discovery, environment, exit status. |
| `zmakefile(5)` | The input file: the two modes, tasks, target kinds, recipe indentation. |

```sh
man zmake
man 5 zmakefile
```

The sources are in `man/` in the repository. They use the mdoc macros, which
`man` reads on Linux, macOS and FreeBSD.

## Install for one user

`zig build` installs the binary and the man pages under one prefix. Use
`~/.local` as the prefix:

```sh
zig build --release -p ~/.local
```

| File | Installed path |
|---|---|
| `zmake` | `~/.local/bin/zmake` |
| `zmake(1)` | `~/.local/share/man/man1/zmake.1` |
| `zmakefile(5)` | `~/.local/share/man/man5/zmakefile.5` |

Put `~/.local/bin` on your `PATH`. Many Linux systems do this in the default
shell profile. On macOS, add this line to `~/.zshrc`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## How man finds the pages

You do not set `MANPATH`. When `MANPATH` is not set, `man` makes its search
path from `PATH`. For each `PATH` entry that ends in `/bin`, it also searches
`../share/man` and `../man`. So `~/.local/bin` on the `PATH` makes `man` search
`~/.local/share/man`.

| System | Program | Rule |
|---|---|---|
| Linux | man-db | `manpath(5)`: the man directories next to each `PATH` entry |
| macOS | `man` and `manpath` | `manpath(1)`: `../share/man` and `../man` for each `/bin` entry |
| FreeBSD | `man` and `manpath` | `manpath(1)`: the same rule as macOS |

`man` reads the page files directly. You do not run `mandb` or `makewhatis`.
Run them only when you want `apropos zmake` to find the pages.

Acceptance scenario 23 checks this rule on the Linux, macOS and FreeBSD CI
runners.

## When MANPATH is set

A `MANPATH` value turns off the search from `PATH`. Do one of these:

- Add the directory to the value: `export MANPATH="$HOME/.local/share/man:$MANPATH"`.
- Start or end the value with a colon. `man` replaces the empty entry with its default search path, which includes the directories from `PATH`.

On macOS, `path_helper` in `/etc/zprofile` sets `MANPATH` only when it is
already set.

## Check the install

```sh
man -w zmake
```

```text
/home/user/.local/share/man/man1/zmake.1
```

When `man -w zmake` prints no path, check that `~/.local/bin` is on the `PATH`
and that `MANPATH` is not set.

## Install for all users

Use `/usr/local` as the prefix. `man` searches `/usr/local/share/man` on each
of the three systems.

```sh
sudo zig build --release -p /usr/local
```
