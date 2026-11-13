---
title: Export and the Environment
description: Control which variables reach the environment of each recipe with export and unexport.
---

Each recipe line runs with an environment. By default, zmake passes its own
environment, plus `MAKEFLAGS` and `MAKELEVEL`. `export` and `unexport` change
the environment, as in GNU Make.

```make
export GOFLAGS = -trimpath
export CGO_ENABLED := 0

VERSION = 1.2.0
export VERSION

unexport DISPLAY

build:
	go build ./...
```

## Which variables a recipe gets

zmake decides for each variable, in this order:

1. `export NAME` adds the variable. `unexport NAME` removes it, also a variable from the environment.
2. A variable from the command line, for example `zmake MODE=fast`, goes to each recipe.
3. A variable from the environment goes with its current value. When the input file changes `PATH`, the recipe gets the new `PATH`.
4. `export` alone and `.EXPORT_ALL_VARIABLES` export each file variable with a valid shell name. `unexport` alone ends this.

Built-in variables such as `MAKE` never go. `SHELL` keeps the value from the
environment: a `SHELL` in the input file changes the shell of zmake, not the
environment of the recipe.

## Forms

| Line | Effect |
|---|---|
| `export NAME` | Exports the variable, also when the input file defines it later |
| `export A B C`, `export $(NAMES)` | Exports each name |
| `export NAME = value` | Sets and exports. All assignment operators work |
| `export define NAME` | Sets a multi-line value and exports it |
| `export override NAME = value` | Sets with the `override` origin and exports |
| `export` | Exports each variable with a valid shell name |
| `unexport NAME` | Removes the variable from the recipe environment |
| `unexport` | Ends `export` with no names |

## Expansion

zmake expands an exported recursive variable for each target, with the
automatic variables of that target:

```make
export BUILD_TARGET = $@

app lib:
	./build.sh   # sees BUILD_TARGET=app, then BUILD_TARGET=lib
```

`$(shell ...)` runs with the environment of zmake, not with the exports, as in
GNU Make 4.3.
