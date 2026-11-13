---
title: Pattern Rules and Variables
description: Variable flavors, automatic variables, functions and pattern rules in zmake.
---

zmake expands variables and resolves pattern rules as GNU Make does. This page
shows the supported forms. The [Compatibility](../../reference/compatibility/)
page lists the forms that stop the build.

## Variable flavors

| Assignment | Flavor |
|---|---|
| `X = value` | Recursive. zmake expands the value each time it uses `X`. |
| `X := value`, `X ::= value` | Simple. zmake expands the value once, at the assignment. |
| `X ?= value` | Recursive, only when `X` has no value. |
| `X += value` | Append. The flavor of `X` does not change. |

A command-line variable overrides the input file and the environment:

```sh
zmake CFLAGS=-g
```

:::note[No built-in variables]
GNU Make defines `CC`, `CXX`, `RM` and other built-in variables. zmake defines
only `MAKE`. Set `CC := cc` in the input file, or give `CC=cc` on the command line.
:::

## Automatic variables

| Variable | Value |
|---|---|
| `$@` | The target |
| `$<` | The first prerequisite |
| `$^` | All prerequisites, without duplicates |
| `$+` | All prerequisites, with duplicates |
| `$*` | The stem of a pattern match |
| `$?` | The prerequisites that are newer than the target |

Each variable also has a `D` form (the directory part) and an `F` form (the
file part), for example `$(@D)` and `$(<F)`.

## Functions

zmake supports four functions and substitution references:

```make
SRCS := $(wildcard src/*.c)
OBJS := $(patsubst src/%.c,obj/%.o,$(SRCS))
DEPS := $(SRCS:.c=.d)
NAME := $(subst -,_,my-app)
REV  := $(shell git rev-parse --short HEAD)
```

Any other function, for example `$(foreach ...)`, stops the build:

```text
Makefile:3: *** unsupported function 'foreach'.  Stop.
```

## Pattern rules

```make
CC := cc
CFLAGS := -O2 -Wall
SRCS := $(wildcard src/*.c)
OBJS := $(patsubst src/%.c,obj/%.o,$(SRCS))

.PHONY: all
all: app

app: $(OBJS)
	$(CC) -o $@ $^

obj/%.o: src/%.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@
```

zmake resolves each target in this order:

1. Use the explicit rules for the target. Merge their prerequisites. The last recipe wins.
2. For an explicit rule without a recipe, take the recipe from a pattern rule.
3. Otherwise, use the viable pattern rule with the shortest stem. The first rule wins a tie.
4. Otherwise, use an existing file, or a `.PHONY` name with no recipe.
5. Otherwise, stop with `No rule to make target`.

A pattern prerequisite is viable when it exists, has an explicit rule or is
phony. zmake also accepts one level of chaining: a second pattern rule can make
the prerequisite. A pattern without `/` matches the file part of a name, and
the directory joins the stem.

:::caution[Order-only prerequisites on pattern rules]
zmake drops the order-only prerequisites of a pattern rule, for example
`obj/%.o: src/%.c | obj`
([ISSUE-007](https://github.com/infrashift/zmake/blob/main/.okfw/issues/issue-007-pattern-rules-drop-order-only-prerequisites--01a1d3419a7f.md)).
Order-only prerequisites on explicit rules work. Until the fix, create the
directory in the recipe with `mkdir -p $(@D)`, as in the example above.
:::

## Cycles

A circular dependency stops zmake. The message shows each rule with its line:

```text
zmake: *** Circular dependency: a (Makefile:1) -> b (Makefile:3) -> a.  Stop.
```

GNU Make drops the circular edge with a warning and continues. zmake does not
continue.
