#!/usr/bin/env bash
# End-to-end acceptance scenarios for zmake. `zig build acceptance` passes the
# binary path as $1. Each scenario runs in its own temporary directory.
# Scenarios 1-3 are the canonical PLAN.md scenarios. Where GNU Make is
# installed, the script compares the output of zmake with GNU Make.
set -u
# Start clean when a make runs this script: an inherited MAKELEVEL or MAKEFLAGS
# changes the output of GNU Make and of zmake.
unset MAKEFLAGS MFLAGS MAKELEVEL

ZMAKE=$(realpath "$1")
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GNU_MAKE=$(command -v make || true)
PASS=0
FAIL=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '%s\n' "$2" | sed 's/^/       | /'; }

expect_eq() { # name expected actual
  if [ "$2" == "$3" ]; then pass "$1"; else fail "$1" "expected: $2"$'\n'"actual:   $3"; fi
}
expect_has() { # name needle haystack
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "missing: $2"$'\n'"in:"$'\n'"$3"; fi
}
expect_not() { # name needle haystack
  if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1" "unexpected: $2"$'\n'"in:"$'\n'"$3"; fi
}
scenario() { # name: create and enter a fresh directory
  printf '%s\n' "$1"
  local dir="$WORK/$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '_')"
  mkdir -p "$dir" && cd "$dir" || exit 2
}
elapsed() { # command...: print the run time in tenths of a second
  local start end
  start=$(date +%s%N); "$@" >/dev/null 2>&1; end=$(date +%s%N)
  echo $(((end - start) / 100000000))
}

scenario "1. The build/ directory (modern mode)"
mkdir build
printf 'build:\n    echo RAN-BUILD\n' > ZMakefile
out=$("$ZMAKE" build 2>&1); code=$?
expect_eq "exit code 0" 0 "$code"
expect_has "recipe runs although ./build exists" "RAN-BUILD" "$out"
expect_has "shadow warning" "warning: target 'build' shadows existing path './build'; prefix with '@build:' to silence" "$out"
printf '@build:\n    echo RAN-BUILD\n' > ZMakefile
out=$("$ZMAKE" build 2>&1)
expect_not "@build silences the warning" "warning" "$out"

scenario "2. Explicit @task with 4-space indentation (modern mode)"
printf 'build:\n    echo step-build\n\n@deploy: build\n    echo step-deploy\n    @echo silent-line\n' > ZMakefile
out=$("$ZMAKE" deploy 2>&1); code=$?
expect_eq "exit code 0" 0 "$code"
expect_eq "build runs, then deploy" "echo step-build|step-build|echo step-deploy|step-deploy|silent-line" "$(printf '%s' "$out" | paste -sd'|')"
printf 'app: main.c\n    cp main.c $@\n' > ZMakefile
touch main.c
"$ZMAKE" >/dev/null 2>&1
out=$("$ZMAKE" 2>&1)
expect_eq "a bare name with \$@ is a file target" "zmake: 'app' is up to date." "$out"

scenario "3. Strict legacy compatibility (legacy mode)"
printf 'int util(void);\nint main(void) { return util(); }\n' > main.c
printf 'int util(void) { return 0; }\n' > util.c
printf 'int helper(void) { return 1; }\n' > helper.c
cat > Makefile <<'EOF'
.PHONY: all clean
CC := gcc
OBJS := main.o util.o helper.o

all: app

app: $(OBJS)
	$(CC) -o $@ $^

%.o: %.c
	$(CC) -c $< -o $@

clean:
	rm -f app $(OBJS)

build:
	echo legacy-build
EOF
if [ -n "$GNU_MAKE" ]; then
  expect_eq "dry run matches GNU Make" "$("$GNU_MAKE" -n 2>&1)" "$("$ZMAKE" -n 2>&1)"
fi
out=$("$ZMAKE" 2>&1)
expect_eq "first run compiles every object" "gcc -c main.c -o main.o|gcc -c util.c -o util.o|gcc -c helper.c -o helper.o|gcc -o app main.o util.o helper.o" "$(printf '%s' "$out" | paste -sd'|')"
expect_eq "second run has nothing to do" "zmake: Nothing to be done for 'all'." "$("$ZMAKE" 2>&1)"
sleep 0.01; touch util.c
out=$("$ZMAKE" 2>&1)
expect_eq "only the dirty object rebuilds" "gcc -c util.c -o util.o|gcc -o app main.o util.o helper.o" "$(printf '%s' "$out" | paste -sd'|')"
if [ -n "$GNU_MAKE" ]; then
  sleep 0.01; touch helper.c
  expect_eq "incremental dry run matches GNU Make" "$("$GNU_MAKE" -n 2>&1)" "$("$ZMAKE" -n 2>&1)"
  "$ZMAKE" >/dev/null 2>&1
fi
mkdir -p clean build
out=$("$ZMAKE" clean 2>&1)
expect_eq ".PHONY clean runs although ./clean exists" "rm -f app main.o util.o helper.o" "$out"
expect_eq "legacy build: stays a file target" "zmake: 'build' is up to date." "$("$ZMAKE" build 2>&1)"
printf 'all:\n    echo spaces\n' > Makefile
out=$("$ZMAKE" 2>&1); code=$?
expect_eq "space-indented recipe is an error" "Makefile:2: *** missing separator.  Stop." "$out"
expect_eq "error exit code 2" 2 "$code"

scenario "4. Parallel jobs and the jobserver"
printf '.PHONY: all a b c d\nall: a b c d\na b c d:\n\tsleep 1\n' > Makefile
t=$(elapsed "$ZMAKE" -j4)
if [ "$t" -lt 20 ]; then pass "-j4 runs 4 one-second jobs in under 2 s ($t/10 s)"; else fail "-j4 too slow: $t/10 s"; fi
t=$(elapsed "$ZMAKE")
if [ "$t" -ge 40 ]; then pass "-j1 runs them one at a time ($t/10 s)"; else fail "-j1 too fast: $t/10 s"; fi
mkdir sub
printf 'all:\n\t@echo "MAKEFLAGS=[$$MAKEFLAGS]"\n' > sub/Makefile
printf '.PHONY: top\ntop:\n\t+$(MAKE) -C sub\n' > top.mk
out=$("$ZMAKE" -f top.mk -j3 2>&1)
expect_has "a recursive zmake sees the jobserver" "--jobserver-auth=" "$out"
out=$("$ZMAKE" -n -f top.mk 2>&1)
expect_has "\$(MAKE) lines run under -n" "-C sub" "$out"
expect_has "the sub-make inherits -n and prints its recipe" 'echo "MAKEFLAGS=[$MAKEFLAGS]"' "$out"
expect_not "the sub-make runs nothing under -n" "MAKEFLAGS=[" "$(printf '%s' "$out" | grep -v '^echo')"
if [ -n "$GNU_MAKE" ]; then
  printf '.PHONY: top\ntop:\n\t+%s\n' "$ZMAKE" > gnu.mk
  t=$(elapsed "$GNU_MAKE" -j2 -f gnu.mk)
  if [ "$t" -ge 18 ] && [ "$t" -lt 30 ]; then pass "zmake obeys a GNU Make -j2 pool ($t/10 s)"; else fail "GNU -j2 pool: $t/10 s"; fi
  printf '.PHONY: top\ntop:\n\t%s\n' "$ZMAKE" > noplus.mk
  out=$("$GNU_MAKE" -j2 -f noplus.mk 2>&1)
  expect_has "without +, zmake falls back to -j1" "jobserver unavailable: using -j1" "$out"
fi

scenario "5. Errors"
printf 'a: b\n\techo a\nb: a\n\techo b\n' > Makefile
out=$("$ZMAKE" 2>&1); code=$?
expect_eq "cycle shows the path with lines" "zmake: *** Circular dependency: a (Makefile:1) -> b (Makefile:3) -> a.  Stop." "$out"
expect_eq "cycle exit code 2" 2 "$code"
printf 'app: nope.c\n\tcc nope.c\n' > Makefile
out=$("$ZMAKE" 2>&1)
expect_eq "missing prerequisite" "zmake: *** No rule to make target 'nope.c', needed by 'app'.  Stop." "$out"
printf '.PHONY: all\nall:\n\t-false\n\techo after\n' > Makefile
out=$("$ZMAKE" 2>&1); code=$?
expect_has "ignored error message" "zmake: [Makefile:3: all] Error 1 (ignored)" "$out"
expect_has "recipe continues after an ignored error" "after" "$out"
expect_eq "ignored error exit code 0" 0 "$code"
printf '.DELETE_ON_ERROR:\nout:\n\techo partial > $@; exit 3\n' > Makefile
out=$("$ZMAKE" 2>&1); code=$?
expect_has "failed recipe message" "zmake: *** [Makefile:3: out] Error 3" "$out"
expect_has "partial target deleted" "zmake: *** Deleting file 'out'" "$out"
expect_eq "failed recipe exit code 2" 2 "$code"
printf 'out:\n    echo partial > $@; exit 3\n' > ZMakefile
out=$("$ZMAKE" 2>&1)
expect_has "modern mode deletes a partial target by default" "zmake: *** Deleting file 'out'" "$out"
rm -f ZMakefile
printf 'ifeq (a,b)\nendif\n' > Makefile
expect_eq "unsupported directive" "Makefile:1: *** unsupported directive 'ifeq'.  Stop." "$("$ZMAKE" 2>&1)"

scenario "6. Special targets"
printf '.SILENT:\n.PHONY: all\nall:\n\techo quiet\n' > Makefile
expect_eq ".SILENT hides the echo" "quiet" "$("$ZMAKE" 2>&1)"
printf '.NOTPARALLEL:\n.PHONY: all a b c\nall: a b c\na b c:\n\tsleep 0.5\n' > Makefile
t=$(elapsed "$ZMAKE" -j4)
if [ "$t" -ge 14 ]; then pass ".NOTPARALLEL forces one job at a time ($t/10 s)"; else fail ".NOTPARALLEL ignored: $t/10 s"; fi
printf 'X = $(foreach a,b,c)\nall: ; @echo $(X)\n' > Makefile
expect_eq "unsupported function" "Makefile:2: *** unsupported function 'foreach'.  Stop." "$("$ZMAKE" 2>&1)"

scenario "7. zmake reads the zmake Makefile"
if [ -n "$GNU_MAKE" ]; then
  for goal in build lint wiki docs-style; do
    expect_eq "dry run of '$goal' matches GNU Make" "$("$GNU_MAKE" -s -C "$ROOT" -n $goal 2>&1)" "$("$ZMAKE" -C "$ROOT" -f Makefile -n $goal 2>&1)"
  done
fi

# The ZMakefile declares the same targets in modern mode. Each dry run must
# match GNU Make on the Makefile, so the two files cannot drift apart.
scenario "8. The zmake ZMakefile matches the Makefile"
if [ -n "$GNU_MAKE" ]; then
  goals=$(sed -n 's/^\.PHONY: //p' "$ROOT/Makefile")
  expect_has "the Makefile lists its targets in .PHONY" "check" "$goals"
  for goal in $goals; do
    expect_eq "ZMakefile dry run of '$goal' matches GNU Make" "$("$GNU_MAKE" -s -C "$ROOT" -f Makefile -n $goal 2>&1)" "$("$ZMAKE" -C "$ROOT" -f ZMakefile -n $goal 2>&1)"
  done
  expect_eq "ZMakefile default goal matches GNU Make" "$("$GNU_MAKE" -s -C "$ROOT" -f Makefile -n 2>&1)" "$("$ZMAKE" -C "$ROOT" -f ZMakefile -n 2>&1)"
fi

scenario "9. Pattern rules keep order-only prerequisites (ISSUE-007)"
mkdir src && printf 'int main(void) { return 0; }\n' > src/main.c
printf 'app: obj/main.o\n\t@echo link $@\nobj/%%.o: src/%%.c | obj\n\tcc -c $< -o $@\nobj:\n\tmkdir -p $@\n' > Makefile
if [ -n "$GNU_MAKE" ]; then
  expect_eq "dry run matches GNU Make" "$("$GNU_MAKE" -s -n 2>&1)" "$("$ZMAKE" -n 2>&1)"
fi
out=$("$ZMAKE" 2>&1); code=$?
expect_eq "exit code 0" 0 "$code"
expect_has "the order-only directory is made first" "mkdir -p obj" "$out"

printf '\nacceptance: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
