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
printf 'load ./ext.so\nall:;@:\n' > Makefile
expect_eq "unsupported directive" "Makefile:1: *** unsupported directive 'load'.  Stop." "$("$ZMAKE" 2>&1)"

scenario "6. Special targets"
printf '.SILENT:\n.PHONY: all\nall:\n\techo quiet\n' > Makefile
expect_eq ".SILENT hides the echo" "quiet" "$("$ZMAKE" 2>&1)"
printf '.NOTPARALLEL:\n.PHONY: all a b c\nall: a b c\na b c:\n\tsleep 0.5\n' > Makefile
t=$(elapsed "$ZMAKE" -j4)
if [ "$t" -ge 14 ]; then pass ".NOTPARALLEL forces one job at a time ($t/10 s)"; else fail ".NOTPARALLEL ignored: $t/10 s"; fi
printf 'X = $(guile (+ 1 2))\nall: ; @echo $(X)\n' > Makefile
expect_eq "unsupported function" "Makefile:2: *** unsupported function 'guile'.  Stop." "$("$ZMAKE" 2>&1)"

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

scenario "10. Functions match GNU Make (Phase 9)"
mkdir -p sub/dir && touch sub/dir/f.c sub/dir/g.h && ln -s sub/dir lnk
cat > Makefile <<'EOF'
SRC := a.c b.o c.h src/d.c
O = $(1)-$(2)-$(3)
P = $(call O,$(1))
S := $$(1)
reverse = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1))) $(firstword $(1)))
$(info filter=[$(filter %.c %.h,$(SRC))] out=[$(filter-out %.c,$(SRC))] find=[$(findstring a,cat)][$(findstring x,cat)])
$(info sort=[$(sort c b  c a)] strip=[$(strip   a   b  )] words=$(words $(SRC)) word=$(word 2,$(SRC)) list=[$(wordlist 2,3,$(SRC))])
$(info first=$(firstword $(SRC)) last=$(lastword $(SRC)) dir=[$(dir $(SRC) /x)] notdir=[$(notdir src/a.c dir/)])
$(info suffix=[$(suffix a.c b src.d/x a.tar.gz)] base=[$(basename a.c src.d/x b a.tar.gz)] join=[$(join a b c,1 2)])
$(info prefix=[$(addprefix x/,a b)] suffix=[$(addsuffix .c,a b)] abs=[$(abspath a/../b ./c /x/./y/..)] real=[$(realpath lnk/f.c nope sub)])
$(info if=[$(if  x ,yes,no)][$(if ,yes,no)][$(if ,yes)] and=[$(and a,b)][$(and a,,b)] or=[$(or ,b,c)][$(or ,)])
$(info foreach=[$(foreach x,a b c,<$(x)>)] gap=[$(foreach x,a b c,$(if $(filter b,$(x)),,$(x)))])
$(info call=[$(call O,a,b,c)] hide=[$(call P,a,b,c)] simple=[$(call S,x)] builtin=[$(call firstword,a b)] reverse=[$(call reverse,a b c)])
$(info value=[$(value O)] origin=$(origin O) $(origin NOPE) $(origin HOME) $(foreach v,a,$(origin v)) flavor=$(flavor O) $(flavor S) $(flavor NOPE))
$(file >out.txt,hello)
$(file >>out.txt,world)
$(info file=[$(file <out.txt)] missing=[$(file <nope.txt)] glob=[$(wildcard sub/dir/*.c)])
$(warning a warning)
all:
	@echo recipe $(info in-recipe)$(words $^) done
EOF
if [ -n "$GNU_MAKE" ]; then
  expect_eq "output matches GNU Make" "$("$GNU_MAKE" -s 2>&1)" "$("$ZMAKE" 2>&1)"
  expect_eq "file written as GNU Make writes it" "$(printf 'hello\nworld')" "$(cat out.txt)"
fi
printf 'X := $(word 0,a b)\nall:;@:\n' > Makefile
expect_eq "word 0 message" "Makefile:1: *** first argument to 'word' function must be greater than 0.  Stop." "$("$ZMAKE" 2>&1)"
printf 'X := $(error boom here)\nall:;@:\n' > Makefile
expect_eq "error message" "Makefile:1: *** boom here.  Stop." "$("$ZMAKE" 2>&1)"
printf 'X := $(let a b,1 2 3,$(a)|$(b)) $(intcmp 3,2,lt,eq,gt)\n$(info $(X))\nall:;@:\n' > Makefile
expect_eq "let and intcmp (GNU Make 4.4)" "1|2 3 gt" "$("$ZMAKE" 2>&1)"

scenario "11. Conditionals, define, override, undefine and eval (Phase 10)"
cat > Makefile <<'EOF'
A = a
E =
R = $(E)
ifeq (a ,a)
$(info ws-before-comma=true)
endif
ifeq ( a,a )
$(info ws-inside=true)
else
$(info ws-inside=false)
endif
ifneq "$(A)" 'b'
$(info quotes=true)
endif
ifdef R
$(info ifdef-R=true)
endif
ifdef E
$(info ifdef-E=true)
else ifeq (2,2)
$(info else-ifeq=true)
else
$(info never)
endif
ifeq (1,2)
  ifeq (bad syntax here
  $(error never)
  endif
endif
define MULTI
line one
	tab line # not a comment
endef
$(info [$(MULTI)] $(flavor MULTI))
define SIMPLE :=
v=$(A)
endef
$(info $(flavor SIMPLE) [$(value SIMPLE)])
override CMD = file-value
$(info CMD=$(CMD) origin=$(origin CMD))
U = 1
undefine U
$(info U=[$(U)] $(origin U))
$(foreach t,a b,$(eval $(t)_OBJ := $(t).o))
$(info evals=$(a_OBJ) $(b_OBJ))
define RULE
gen-$(1):
	@echo making $$@
endef
$(eval $(call RULE,x))
all: gen-x
ifeq ($(A),a)
	@echo branch-a
else
	@echo branch-other
endif
	@echo after
EOF
if [ -n "$GNU_MAKE" ]; then
  expect_eq "output matches GNU Make" "$("$GNU_MAKE" -s CMD=cmdline gen-x all 2>&1)" "$("$ZMAKE" CMD=cmdline gen-x all 2>&1)"
  for src in 'ifeq (a,a)\nX=1\n' 'endif\n' 'ifeq (a,a)\nelse\nelse\nendif\n' 'ifeq a,a\nendif\n' 'define X\nabc\n' 'ifeq (a,a) junk\nendif\nall:;@echo ok\n'; do
    printf "$src" > Makefile
    expect_eq "message for '$(printf "$src" | head -1)' matches GNU Make" "$("$GNU_MAKE" -s 2>&1 | sed 's/^make:/zmake:/')" "$("$ZMAKE" 2>&1)"
  done
fi
printf 'build:\nifdef FAST\n    @echo fast\nelse\n    @echo slow\nendif\n' > ZMakefile
expect_eq "modern mode: a conditional selects recipe lines" "slow|fast" "$("$ZMAKE" build 2>&1)|$("$ZMAKE" build FAST=1 2>&1)"
rm -f ZMakefile
cat > Makefile <<'EOF'
define CANNED
@echo one
-false
echo three
endef
define FAIL
false
echo after-fail
endef
canned:
	$(CANNED)
fail:
	$(FAIL)
EOF
if [ -n "$GNU_MAKE" ]; then
  for goal in canned fail; do
    expect_eq "canned recipe '$goal' runs line by line as in GNU Make" "$("$GNU_MAKE" $goal 2>&1 | sed 's/^make:/zmake:/'; echo "exit=${PIPESTATUS[0]}")" "$("$ZMAKE" $goal 2>&1; echo "exit=$?")"
  done
fi
printf 'all:\n\t@echo $(eval Z := 1)z\n' > Makefile
expect_eq "eval in a recipe stops" "Makefile:2: *** \$(eval ...) in a recipe is not supported.  Stop." "$("$ZMAKE" 2>&1)"

scenario "12. include and MAKEFILE_LIST (Phase 11)"
mkdir -p mk
printf 'A_FILE := $(lastword $(MAKEFILE_LIST))\nX += from-a\ninclude mk/b.mk\n' > mk/a.mk
printf 'X += from-b\nb-target:\n\t@echo in b\n\t@false\n' > mk/b.mk
printf 'ifeq (a,a)\n' > open.mk
printf 'X := 1\n$(error in-included)\n' > err.mk
cat > Makefile <<'EOF'
X = main
FILES = mk/a.mk
include $(FILES)
-include nope.mk missing.mk
sinclude nope2.mk
$(info X=$(X) list=[$(MAKEFILE_LIST)] a=$(A_FILE))
all: b-target
EOF
if [ -n "$GNU_MAKE" ]; then
  expect_eq "output and recipe error match GNU Make" "$("$GNU_MAKE" 2>&1 | sed 's/^make:/zmake:/')" "$("$ZMAKE" 2>&1)"
  for src in 'include nope.mk\nall:;@:\n' 'include open.mk\nendif\nall:;@echo ok\n' 'include err.mk\nall:;@:\n'; do
    printf "$src" > Makefile
    expect_eq "message for '$(printf "$src" | head -1)' matches GNU Make" "$("$GNU_MAKE" 2>&1 | sed 's/^make:/zmake:/')" "$("$ZMAKE" 2>&1)"
  done
fi
mkdir -p rules && printf 'R1 := 1\n' > rules/a.mk && printf 'R2 := 2\nHERE := $(dir $(lastword $(MAKEFILE_LIST)))\n' > rules/b.mk
printf 'include rules/*.mk\n$(info $(MAKEFILE_LIST) $(HERE) $(R1)$(R2))\nall:;@:\n' > Makefile
if [ -n "$GNU_MAKE" ]; then
  expect_eq "include expands globs as GNU Make does" "$("$GNU_MAKE" 2>&1)" "$("$ZMAKE" 2>&1)"
fi
printf 'include Makefile\nall:;@:\n' > Makefile
expect_has "a file that includes itself stops" "nest more than 64 levels" "$("$ZMAKE" 2>&1)"
printf 'include gen.mk\ngen.mk:\n\techo X=1 > $@\nall:;@:\n' > Makefile
expect_has "zmake says that it does not remake included files" "zmake does not remake included files; make 'gen.mk' first" "$("$ZMAKE" 2>&1)"

scenario "13. export and unexport (Phase 12)"
cat > Makefile <<'EOF'
FILE_ONLY = file
export EXP1 = exported-$(FILE_ONLY)
export EXP2 := simple
EXP3 = later
export EXP3
NAMES = EXP4 EXP5
EXP4 = four
EXP5 = five
export $(NAMES)
ENV_CHANGED = changed-in-file
unexport ENV_UNEXPORTED
export EXP6
EXP6 = defined-after-export
export define EXP7
multi
endef
export TARGET = $@
all:
	@env | grep -E '^(FILE_ONLY|EXP[0-9]|ENV_[A-Z]+|CLI_VAR|TARGET)=' | sort
	@echo "shell: $(shell env | grep -E '^(EXP1|ENV_CHANGED)=' | sort | tr '\n' ' ')"
EOF
if [ -n "$GNU_MAKE" ]; then
  expect_eq "recipe environment matches GNU Make" \
    "$(ENV_KEEP=e ENV_CHANGED=e ENV_UNEXPORTED=e "$GNU_MAKE" CLI_VAR=cli 2>&1)" \
    "$(ENV_KEEP=e ENV_CHANGED=e ENV_UNEXPORTED=e "$ZMAKE" CLI_VAR=cli 2>&1)"
  printf 'A = 1\nB.C = 2\nlower = 3\nexport\nunexport A\nall:\n\t@env | grep -E "^(A|B\\.C|lower|MAKE|CC)=" | sort\n' > Makefile
  expect_eq "export with no names matches GNU Make" "$("$GNU_MAKE" 2>&1)" "$("$ZMAKE" 2>&1)"
  printf '.EXPORT_ALL_VARIABLES:\nX = 1\nall:\n\t@env | grep -E "^X="\n' > Makefile
  expect_eq ".EXPORT_ALL_VARIABLES matches GNU Make" "$("$GNU_MAKE" 2>&1)" "$("$ZMAKE" 2>&1)"
  printf 'override export X = 1\nexport override Y = 2\nall:\n\t@env | grep -E "^(X|Y)=" | sort\n' > Makefile
  expect_eq "override export matches GNU Make" "$("$GNU_MAKE" X=cli Y=cli 2>&1)" "$("$ZMAKE" X=cli Y=cli 2>&1)"
fi

scenario "14. vpath and VPATH (Phase 13)"
mkdir -p src inc lib g z
cat > probe.sh <<'EOS'
cd "$1" || exit 2
mkdir -p src inc lib
echo 'int main(void){return 0;}' > src/main.c
echo 'int u;' > src/util.c
echo '#define X 1' > inc/x.h
printf 'VPATH = src\nvpath %%.h inc\napp: main.o util.o\n\t@echo link $@ from $^\n%%.o: %%.c x.h\n\t@echo compile $< into $@ with $^\n\t@touch $@\n' > Makefile
"$2" 2>&1; "$2" 2>&1
sleep 1; touch inc/x.h; "$2" 2>&1
rm -f ./*.o
touch lib/libz.a
printf 'vpath %%.a lib\nall: libz.a\n\t@echo all uses $^\nlibz.a: z.c\n\t@echo rebuild $@\n' > M2; touch z.c; sleep 1; touch lib/libz.a; "$2" -f M2 2>&1
sleep 1; touch z.c; "$2" -f M2 2>&1
printf 'vpath %%.c src\nvpath %%.c\nall: main.c\n\t@echo $<\n' > M3; "$2" -f M3 2>&1 | sed 's/^[a-z]*make:/make:/'
printf 'VPATH = nope:src inc\nall: main.c x.h\n\t@echo $^\n' > M4; "$2" -f M4 2>&1
printf '.PHONY: main.c\nVPATH = src\nall: main.c\n\t@echo [$^]\nmain.c:\n\t@echo phony main.c\n' > M5; "$2" -f M5 2>&1
EOS
if [ -n "$GNU_MAKE" ]; then
  expect_eq "directory search matches GNU Make" "$(bash probe.sh g "$GNU_MAKE")" "$(bash probe.sh z "$ZMAKE")"
fi

printf '\nacceptance: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
