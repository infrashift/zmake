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

zmake defines the built-in variables of GNU Make, such as `CC`, `CXX`, `RM`,
`COMPILE.c` and `LINK.o`. Their origin is `default`. `-R` leaves them out.

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

zmake supports the GNU Make functions and substitution references:

```make
SRCS := $(wildcard src/*.c)
OBJS := $(patsubst src/%.c,obj/%.o,$(SRCS))
DEPS := $(SRCS:.c=.d)
NAME := $(subst -,_,my-app)
REV  := $(shell git rev-parse --short HEAD)
```

See [Functions](../../reference/functions/) for the full list.

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

:::tip[Order-only prerequisites]
A pattern rule can have order-only prerequisites, for example
`obj/%.o: src/%.c | obj`. zmake makes `obj` first, but a newer `obj` does not
make the object out of date. The order-only prerequisites must also exist or
have a rule. Otherwise the pattern rule does not apply.
:::

## Built-in rules

zmake has the built-in implicit rules of GNU Make 4.3, for example
`%.o: %.c`, `%.o: %.cpp`, `%: %.o` and `%.c: %.y`. With only this line in the
input file, `zmake` compiles and links `tool.c`:

```make
all: tool
```

```text
cc     tool.c   -o tool
```

- The rules of the input file come first. A rule with the same target and prerequisite replaces a built-in rule. Without a recipe, it cancels the built-in rule.
- `-r`, or `MAKEFLAGS += -r` in the input file, turns the built-in rules off.
- Each built-in rule needs its suffixes in `.SUFFIXES`. `.SUFFIXES:` with no names turns them off.
- zmake first tries rules whose prerequisites exist or have rules. Only then does it try a chain of two rules.
- A rule with the target `%` alone does not make a file with a known suffix, such as `main.c`.

## Suffix rules

An old-style suffix rule becomes a pattern rule when `.SUFFIXES` has its
suffixes: `.c.o:` is `%.o: %.c`, and `.c:` is `%: %.c`.

```make
.SUFFIXES: .md .html
.md.html:
	pandoc $< -o $@
```

## Double-colon rules

A target with `::` rules has one independent recipe for each rule:

```make
docs:: api.yaml
	./gen-api-docs api.yaml
docs:: guide.md
	./render guide.md
```

- A rule runs when the target is missing, or when one of the prerequisites of that rule is newer.
- A rule with no prerequisites always runs.
- The rules run in file order. A failure stops the later rules.
- `$^` and `$?` give the prerequisites of each rule.
- A target cannot have both `:` and `::` rules.

## Cycles

A circular dependency stops zmake. The message shows each rule with its line:

```text
zmake: *** Circular dependency: a (Makefile:1) -> b (Makefile:3) -> a.  Stop.
```

GNU Make drops the circular edge with a warning and continues. zmake does not
continue.
