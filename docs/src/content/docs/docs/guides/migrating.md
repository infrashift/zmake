---
title: Migrating from GNU Make
description: Run an existing Makefile with zmake, then move it to modern mode one step at a time.
---

zmake reads an existing `Makefile` in legacy mode, with GNU Make semantics. A
move to modern mode is optional, and you can do it one step at a time.

## Step 1: run the Makefile in legacy mode

1. In the project directory, run `zmake -n`.
2. Compare the output with `make -n`.
3. Fix each error that zmake reports. The next section lists the common errors.

zmake stops at the first feature outside its scope. The message gives the file
and the line:

```text
Makefile:7: *** unsupported directive 'include'.  Stop.
Makefile:12: *** unsupported directive 'export'.  Stop.
```

## Common errors

| Error | Cause | Fix |
|---|---|---|
| `unsupported directive 'include'` | `include`, `-include` | Merge the included file, or keep GNU Make for this file. |
| `unsupported directive 'export'` | `export`, `unexport`, `vpath` | Pass the variable on the recipe line, for example `X=$(X) ./run.sh`. |
| `$(eval ...) in a recipe is not supported` | `$(eval ...)` in a recipe | Move the eval to a line of its own, outside the recipe. |
| An empty command | A built-in variable such as `$(CC)` | Set `CC := cc` in the input file. |

zmake also rejects double-colon rules (`a:: b`), target-specific variables
(`a: CC = x`) and shell assignments (`X != cmd`).

## Step 2: move to modern mode

1. Rename `Makefile` to `ZMakefile`, or run `zmake --modern`.
2. Run `zmake -n` and compare the output with step 1.
3. Remove the `.PHONY` list. Declare each task as `@name:`.
4. Check each file target with a bare name. Its recipe needs `$@`.
5. Change tab indentation to spaces, if you prefer spaces.

:::tip[Keep .PHONY during the move]
Modern mode still reads `.PHONY`. Remove the list only after `zmake -n` gives
the same output.
:::

## Differences after the move

- A bare name without `$@` is a phony target. It runs also when a path with the same name exists. See [Tasks and Phony Inference](../tasks-and-phony-inference/).
- A failed recipe line deletes a partial file target. List the target in `.PRECIOUS` to keep it.
- GNU Make cannot read a `ZMakefile` with space-indented recipes. Keep a `Makefile` when your team also uses GNU Make.
