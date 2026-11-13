---
title: Target-Specific Variables
description: Set a variable for one target, for a pattern of targets, and for the prerequisites that they build.
---

A target-specific variable has a value only for one target and for the
prerequisites that the target builds, as in GNU Make.

```make
CFLAGS = -O2

debug: CFLAGS += -g -O0
debug: app

release: app

app: main.o util.o
	$(CC) $(CFLAGS) -o $@ $^
```

`zmake debug` compiles `main.o`, `util.o` and `app` with `-O2 -g -O0`.
`zmake release` uses `-O2`.

## Forms

| Line | Effect |
|---|---|
| `app: VAR = value` | All assignment operators work: `=`, `:=`, `::=`, `?=`, `+=` |
| `app lib: VAR = value` | The same assignment for each target |
| `%.o: CFLAGS += -fPIC` | A pattern-specific variable for each target that matches |
| `app: override VAR = value` | Wins over a variable from the command line |
| `app: export VAR = value` | Also goes to the environment of the recipe |
| `app: private VAR = value` | Only for `app` itself. Prerequisites do not inherit it |

## Rules

- A prerequisite inherits the variables of the target that first needs it. zmake builds a shared prerequisite once, in that context.
- `+=` adds to the value that the target sees otherwise: the inherited value, else the global value.
- `:=` expands when zmake builds the context of the target, so it sees the other variables of the target.
- When two patterns match, the one with the shorter stem wins: `lib/%.o` wins over `%.o` for `lib/a.o`.
- A variable from the command line wins, unless the assignment has `override`.
- Target-specific variables change recipes and the recipe environment. They do not change the prerequisite lists, because zmake expands those when it reads the rule.

## Order of a serial build

Without `-j`, zmake runs the recipes in the depth-first order of GNU Make. It
builds the prerequisites of the first goal from left to right, then that goal.
Then it goes on to the next goal.
