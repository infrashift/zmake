# zmake development gates. Plain GNU Make syntax, so zmake can run this file too.

ZIG ?= zig
PYTHON ?= python3
ZIG_SOURCES := build.zig src tests

.PHONY: all build test lint fmt acceptance wiki docs-style docs-demo docs-dev docs-build check

all: check

## build: compile the zmake binary into zig-out/bin
build:
	$(ZIG) build

## test: run the unit tests and the mode tests
test:
	$(ZIG) build test --summary all

## lint: check the formatting and the Power of 10 rules
lint:
	$(ZIG) fmt --check $(ZIG_SOURCES)
	$(PYTHON) -I scripts/nasa-lint.py

## fmt: format the Zig sources in place
fmt:
	$(ZIG) fmt $(ZIG_SOURCES)

## acceptance: run the end-to-end scenarios against the built binary
acceptance:
	$(ZIG) build acceptance

## wiki: validate the OKF wiki
wiki:
	okfw validate --all
	okfw validate --okf

## docs-style: check the documentation against ASD-STE100 rules
docs-style:
	$(PYTHON) -I scripts/ste-check.py

## docs-demo: regenerate the landing-page demo output with zmake itself
docs-demo: build
	rm -rf zig-out/docs-demo
	mkdir -p zig-out/docs-demo/build
	cp docs/src/demo/ZMakefile zig-out/docs-demo/
	cd zig-out/docs-demo && touch main.c util.c && ../bin/zmake -n deploy > ../../docs/src/demo/output.txt 2>&1

## docs-dev: run the Astro Starlight site locally (bun)
docs-dev:
	cd docs && bun install && bun --bun run dev

## docs-build: build the site into docs/dist (the same build as the Pages deploy)
docs-build:
	cd docs && bun install --frozen-lockfile && bun --bun run build

## check: run every gate
check: lint test acceptance wiki docs-style
