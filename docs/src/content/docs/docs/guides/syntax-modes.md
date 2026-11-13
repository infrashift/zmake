---
title: Syntax Modes
description: How zmake selects legacy or modern mode, and which recipe indentation each mode accepts.
---

zmake reads each input file in one of two modes. **Legacy mode** keeps strict
POSIX and GNU Make semantics. **Modern mode** removes the `.PHONY` boilerplate
and accepts recipe lines that start with spaces.

## Mode selection

zmake applies the first rule that matches:

1. Use `--modern` or `--legacy` when the command line gives one.
2. Otherwise, use the basename of the `-f` file. `ZMakefile` and `Make.zig.mk` select modern mode.
3. Otherwise, search the directory in this order: `ZMakefile`, `Make.zig.mk`, `GNUmakefile`, `makefile`, `Makefile`.

Any other `-f` file name selects legacy mode. A directory with a `ZMakefile` and
a `Makefile` gives modern mode, because zmake finds the `ZMakefile` first.

```sh
zmake                      # ZMakefile first, then the GNU names
zmake -f build.mk          # legacy mode
zmake -f build.mk --modern # modern mode for any file name
```

## Recipe lines

| Mode | A recipe line starts with |
|---|---|
| Legacy | A tab. A line with spaces after a rule is the error `missing separator`. |
| Modern | A tab, or two or more spaces. |

In modern mode, the first indented line sets the indent of the block. zmake
removes that indent from each line of the block. These lines end a block:

- A non-blank line at column 0 ends the block.
- Blank lines and comment lines do not end the block.
- A recipe line with less indent than the block is an error.

```make
# ZMakefile
test:
    go vet ./...
    go test ./...

    # The comment and the blank line do not end the block.
    go test -race ./...
```

:::caution[Assignments in modern mode]
Inside a recipe block, each line with two or more spaces is a recipe line. Put
variable assignments at column 0.
:::

## What stays the same

Both modes use the same expansion, the same pattern rules and the same
executor. Modern mode still reads `.PHONY`, so a Makefile snippet works in a
`ZMakefile` with no change. Only these items differ:

| Item | Legacy | Modern |
|---|---|---|
| Recipe indentation | Tab | Tab or spaces |
| `@name:` and `task name:` | Ordinary target names | Task declarations |
| Bare names without `.PHONY` | File targets | Phony targets, by [inference](../tasks-and-phony-inference/) |
| Partial file after a failed recipe | Kept, unless `.DELETE_ON_ERROR` | Deleted, unless `.PRECIOUS` |

The last row comes from
[ADR-0007](../../project/decisions/#adr-0007-delete-partial-targets-by-mode).
GNU Make keeps a partial file, and the next run then sees an up-to-date target
with bad content. Modern mode removes this trap.
