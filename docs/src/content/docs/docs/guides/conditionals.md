---
title: Conditionals and define
description: Use ifeq, ifdef, define, override, undefine and eval in zmake.
---

zmake reads the input file line by line. A conditional sees the variables that
the lines above it define, as in GNU Make.

## Conditionals

```make
OS := $(shell uname -s)

ifeq ($(OS),Darwin)
LDFLAGS += -framework CoreFoundation
else ifeq ($(OS),Linux)
LDFLAGS += -lrt
else
$(error unsupported system: $(OS))
endif

ifdef DEBUG
CFLAGS += -g -O0
endif
```

| Directive | The branch is in effect when |
|---|---|
| `ifeq (a,b)`, `ifeq "a" "b"`, `ifeq 'a' 'b'` | The expansions of `a` and `b` are equal |
| `ifneq (a,b)` | The expansions are different |
| `ifdef NAME` | The variable has a value that is not empty. zmake does not expand the value |
| `ifndef NAME` | The variable has no value, or an empty one |

- In the `(a,b)` form, zmake drops the white space before and after the comma. Other white space counts: `ifeq ( a,a )` is false.
- `else` can start another test: `else ifeq (...)`.
- Each file must close its conditionals. A missing `endif` stops zmake with `missing 'endif'`.
- In a branch that is not in effect, zmake reads only the conditional lines. The other lines can have any syntax.

### Conditionals inside a recipe

A conditional line inside a recipe does not end the rule. It selects recipe
lines:

```make
release:
ifeq ($(SIGN),yes)
	gpg --detach-sign app.tar
endif
	scp app.tar server:/srv/
```

Start the conditional line at column 0. In modern mode, a line with spaces in a
recipe block is a recipe line, so put the directive at column 0 there too.

## define

`define` sets a variable to text with several lines:

```make
define BANNER
=============
 Build done.
=============
endef

done:
	$(info $(BANNER))
```

- The operator after the name sets the flavor: `define X :=` is simple, `define X +=` appends. Without one, the variable is recursive.
- The body keeps tabs and `#`. Nested `define` blocks need their own `endef`.
- `override define` gives the variable the `override` origin.

### Canned recipes

A recipe line that expands to several lines runs each line as its own command,
as in GNU Make. Each line has its own `@`, `-` and `+` prefixes, and a failed
line stops the recipe:

```make
define BUILD_DOCS
@echo building docs
-rm -rf site/
mkdocs build
endef

docs:
	$(BUILD_DOCS)
```

## override and undefine

```make
override CFLAGS += -Wall
undefine LEGACY_FLAGS
```

- An `override` assignment wins over a variable from the command line. Later assignments without `override` have no effect on it.
- `undefine` removes a variable. A command-line variable stays, unless the line has `override`.

## eval

`$(eval text)` reads `text` as more input. Use it to make rules from a template:

```make
define PROGRAM
$(1): $(1).o
	$$(CC) -o $$@ $$^
ALL += $(1)
endef

$(foreach p,server client,$(eval $(call PROGRAM,$(p))))

all: $(ALL)
```

:::caution[Differences from GNU Make]
- An eval takes effect after the statement that calls it. In
  `X := $(eval Y := 1)$(Y)`, `Y` is still empty when zmake expands `$(Y)`. Put
  the eval on its own line.
- A recipe cannot call `eval`. zmake stops with
  `$(eval ...) in a recipe is not supported`.
:::
