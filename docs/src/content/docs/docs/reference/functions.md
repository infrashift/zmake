---
title: Functions
description: The GNU Make functions that zmake supports, with the differences from GNU Make.
---

zmake supports the GNU Make functions. The output matches GNU Make 4.3. A
function name must have white space after it: `$(if)` is a variable reference,
not a function call.

## Text functions

| Function | Result |
|---|---|
| `$(subst from,to,text)` | Each `from` in `text` replaced with `to` |
| `$(patsubst pattern,replacement,text)` | Each word that matches `pattern` replaced; `%` is the stem |
| `$(strip text)` | The words with one space between them |
| `$(findstring find,in)` | `find` when `in` contains it, else empty |
| `$(filter patterns,text)` | The words that match one of the patterns |
| `$(filter-out patterns,text)` | The words that match none of the patterns |
| `$(sort list)` | The words in lexical order, without duplicates |
| `$(word n,text)` | Word `n`, counted from 1 |
| `$(wordlist s,e,text)` | Words `s` to `e` |
| `$(words text)` | The number of words |
| `$(firstword text)`, `$(lastword text)` | The first or the last word |

## File name functions

| Function | Result |
|---|---|
| `$(dir names)` | The directory part of each name, with the final `/`; `./` without one |
| `$(notdir names)` | The part after the last `/` |
| `$(suffix names)` | The suffix of each name that has one |
| `$(basename names)` | Each name without its suffix |
| `$(addsuffix s,names)`, `$(addprefix p,names)` | Each name with the suffix or the prefix |
| `$(join a,b)` | The words of `a` and `b`, joined pair by pair |
| `$(wildcard patterns)` | The existing paths that match, sorted for each pattern |
| `$(abspath names)` | Absolute paths without `.` and `..`; symbolic links stay |
| `$(realpath names)` | Canonical paths of the names that exist |

## Conditional functions

`if`, `and`, `or` and `intcmp` expand only the arguments that they need. An
unused `$(error ...)` does not stop the build.

```make
CC := $(if $(shell command -v clang),clang,gcc)
CHECK = $(and $(wildcard .git),$(shell git status --porcelain))
TAG = $(or $(VERSION),$(shell git describe --tags),dev)
```

| Function | Result |
|---|---|
| `$(if cond,then[,else])` | `then` when `cond` is not empty after stripping, else `else` |
| `$(or a,b,...)` | The first argument that is not empty |
| `$(and a,b,...)` | Empty when an argument is empty, else the last argument |
| `$(intcmp lhs,rhs[,lt[,eq[,gt]]])` | The part for the integer comparison. A missing `gt` part is the `eq` part |

## Loops and user functions

```make
DIRS := lib app tools
CLEAN := $(foreach d,$(DIRS),$(d)/build)

pair = $(1)=$(2)
FLAGS := $(call pair,MODE,release)

reverse = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1))) $(firstword $(1)))
```

| Function | Result |
|---|---|
| `$(foreach var,list,text)` | `text` expanded once for each word, joined with one space |
| `$(let a b,list,text)` | `text` with `a` set to the first word and `b` to the rest |
| `$(call var,arg1,arg2,...)` | The value of `var` with `$(1)`, `$(2)`, ... set |

- `$(0)` is the name of the variable. A missing argument is empty.
- `call` expands a recursive variable. A simple variable gives its value with no expansion, as in GNU Make.
- A `call` can call itself. The limit is 64 nested frames.
- A call takes at most 16 arguments.

## Variable and message functions

| Function | Result |
|---|---|
| `$(value var)` | The value of `var` with no expansion |
| `$(origin var)` | `undefined`, `default`, `environment`, `file`, `command line` or `automatic` |
| `$(flavor var)` | `undefined`, `recursive` or `simple` |
| `$(error text)` | Stops with `file:line: *** text.  Stop.` |
| `$(warning text)` | Prints `file:line: text` on stderr |
| `$(info text)` | Prints `text` on stdout |
| `$(shell command)` | The output of the command, with newlines turned into spaces |
| `$(file >name,text)`, `$(file >>name,text)` | Writes or appends `text` and a final newline |
| `$(file <name)` | The content of the file without its final newline |

A line that has only a function call, such as `$(info ...)`, is valid when the
expansion is empty.

## eval

`$(eval text)` reads `text` as more input, for example a rule from a template.
See [Conditionals and define](../../guides/conditionals/#eval). An eval takes
effect after the statement that calls it, and a recipe cannot call `eval`.

## Not supported

- `$(guile ...)` stops the build. zmake has no Guile interpreter.
