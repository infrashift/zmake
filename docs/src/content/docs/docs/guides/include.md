---
title: Include Files
description: Split the input file with include, -include and sinclude, and read MAKEFILE_LIST.
---

`include` reads other input files at the point of the directive:

```make
include config.mk rules/*.mk
-include local.mk

$(info read: $(MAKEFILE_LIST))
```

- zmake expands the names, then reads each file in order.
- `-include` and `sinclude` skip a file that does not exist.
- A name is a path relative to the working directory. zmake does not search other directories.
- Each file must close its own conditionals.
- Messages and recipe errors name the file of each line, for example `zmake: *** [rules/c.mk:4: app] Error 1`.

## MAKEFILE_LIST

`MAKEFILE_LIST` lists each input file in the order that zmake reads it. The
last word is the file that zmake reads now:

```make
# rules/c.mk
HERE := $(dir $(lastword $(MAKEFILE_LIST)))
```

## A missing file

A missing file stops zmake after it reads all input, as in GNU Make:

```text
Makefile:1: deps.mk: No such file or directory
zmake: *** No rule to make target 'deps.mk'.  Stop.
```

:::caution[No remaking of include files]
GNU Make makes a missing include file when a rule can make it, then reads
all input again. zmake does not. When a rule exists, zmake stops with
`zmake does not remake included files; make 'deps.mk' first`. Make the file
in an earlier step, or use `-include` for generated dependency files.
:::
