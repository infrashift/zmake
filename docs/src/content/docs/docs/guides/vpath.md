---
title: Directory Search
description: Find prerequisites in other directories with VPATH and vpath.
---

`VPATH` and `vpath` tell zmake where to look for a file that is not in the
working directory, as in GNU Make.

```make
VPATH = src:lib
vpath %.h include

app: main.o util.o
	$(CC) -o $@ $^

%.o: %.c config.h
	$(CC) -c $< -o $@
```

With `src/main.c` and `include/config.h`, the compile line is
`cc -c src/main.c -o main.o`. `$<` gives the found path.

## The search

For a file that is not in the working directory, zmake tries:

1. The `vpath` directives whose pattern matches the name, in file order.
2. The directories of `VPATH`, in order.

Directory lists use colons or white space. zmake does not search an absolute
name or a phony target.

| Directive | Effect |
|---|---|
| `vpath %.h include:third_party` | Search two directories for names that match `%.h` |
| `vpath %.h` | Remove the entries for `%.h` |
| `vpath` | Remove all `vpath` entries |
| `VPATH = src lib` | Search these directories for each missing file |

## Automatic variables

`$<`, `$^`, `$+` and `$?` give the found paths. `$@` is always the target name.

## Targets in a search directory

Directory search also finds targets. Assume `lib/libz.a` exists and
`vpath %.a lib`:

- When `libz.a` is up to date, zmake does not run its recipe. A target that needs `libz.a` gets `lib/libz.a` in `$^`.
- When `libz.a` is out of date, zmake runs its recipe in the working directory. The result is `./libz.a`, and `$^` then gives `libz.a`.

`GPATH` is not supported.
