---
title: Tasks and Phony Inference
description: How modern mode classifies each target as a task, an inferred phony target or a file.
---

In GNU Make, a target without `.PHONY` is a file. A `build:` rule does nothing
when a `build/` directory exists. Each project repeats a `.PHONY` list, users
forget entries, and the failure is silent. Modern mode removes this problem.

## Target kinds

| Kind | Meaning |
|---|---|
| `file` | zmake compares modification times. The recipe runs when the target is missing or older than a prerequisite. |
| `explicit_phony` | The recipe always runs. zmake never examines the disk for the target. |
| `inferred_phony` | Modern mode only. The recipe always runs. zmake examines the disk only for the collision warning. |

## Declare a task

`@name:` and `task name:` declare a task. A task is `explicit_phony`.

```make
# ZMakefile
@deploy: build
    ./deploy.sh app

task release: test
    git tag v1.0.0
```

- In a rule with several targets, each target carries `@`, or none does.
- `task:` with no name declares a plain target with the name `task`.
- In legacy mode, `@name` and `task` are ordinary target names.

## Classification rules

In modern mode, zmake applies the first rule that matches:

1. **Rule A.** A task, or a target that `.PHONY` names, is `explicit_phony`.
2. **Rule B.** A name with `/` or `.`, a pattern rule, or a recipe with `$@` gives `file`.
3. **Rule C.** Any other target with a rule is `inferred_phony`.

A name with no rule (a prerequisite only) is always a `file`.

```make
# ZMakefile
build:              # Rule C: inferred_phony
    $(CC) -o app main.c

app: main.c         # Rule B: the recipe refers to $@, so a file
    $(CC) -o $@ main.c

app.tar: app        # Rule B: the name has a dot, so a file
    tar -cf $@ app

@deploy: app.tar    # Rule A: a task
    ./deploy.sh app.tar
```

In legacy mode, a target is `explicit_phony` when `.PHONY` names it. Any other
target is a `file`.

## The `$@` scan

zmake reads the unexpanded recipe to find `$@`. It matches `$@`, `$(@)`,
`${@}`, `$(@D)`, `$(@F)`, `${@D}` and `${@F}`.

:::caution[A bare file name needs `$@`]
A file target with a bare name, for example `app`, needs `$@` in its recipe.
Without `$@`, the target is `inferred_phony` and always runs. A recipe that
hides `$@` in a variable also gives `inferred_phony`.
:::

## The collision warning

An `inferred_phony` target can have the same name as a file or a directory.
zmake then runs the recipe and prints a warning:

```text
zmake: warning: target 'test' shadows existing path './test'; prefix with '@test:' to silence
```

To remove the warning, declare the target as a task: `@test:`. A task never
examines the disk, so it gives no warning.

## Why the rules use the recipe and the name

The classification does not depend on the state of the disk. A rule that
infers a phony target "when no file exists" gives a different result after
each build. See
[ADR-0004](../../project/decisions/#adr-0004-modern-mode-declares-tasks-and-infers-phony-targets).
