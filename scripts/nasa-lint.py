#!/usr/bin/env python3
"""Check the Zig sources in src/ against the scriptable NASA/JPL Power of 10 rules.

ADR-0003 adapts the rules to Zig. This script checks:
  R1  no direct or indirect recursion (same-file calls and module-qualified calls)
  R2  no `while (true)` loops: every loop needs a visible bound
  R4  function bodies of 60 lines or fewer
  R5  an average of 2 or more assertions per function
  R7  no swallowed errors (`catch {}`), no `catch unreachable`, no discarded call results
  R9  no function pointer types of our own (`*const fn`)
Test blocks and test helpers (a name that starts with `test` or ends with `Test`)
are exempt. Suppress one finding with a comment on the same line or
the line above: `// nasa-lint: allow(R7) <reason>`.
Run from the repository root: python3 -I scripts/nasa-lint.py [--verbose]
With --verbose, the script lists each function with fewer than 2 assertions.

Functions: `[pub] [export|extern] [inline|noinline] fn name(`, also a quoted
name `@"name"`. The body opens on the first line that ends with `{` outside
the parameter list, or on the line of a one-line function `fn f() void {}`.
Each call and each assertion belongs to the innermost function that holds
its line, so a nested function does not add to the enclosing function.

Call graph (R1): a node is the file path from the root and the function key.
The key holds the names of the enclosing `const Name = struct {` containers
and `F()` for each enclosing function F, for example `Mutable.toFloat` or
`ArrayList().append`. A plain call `f(` looks for f in the container of the
caller, then in each outer container, then in the file. A call through
`self.`, `Self.` or `@This().` looks in the container of the caller only. A
call `alias.f(` of `const alias = @import("x.zig")` goes to the function f of
x.zig, relative to the directory of the file. A builtin `@f(`, a decl literal
`.f(` and a method call on an expression `x().f(` give no edge.
"""
import pathlib
import posixpath
import re
import sys

MAX_FN_LINES = 60
MIN_ASSERT_AVG = 2.0
MAX_SIGNATURE_LINES = 200

NAME = r'(?:[A-Za-z_]\w*|@"")'
FN_RE = re.compile(r"^\s*(?:pub\s+)?(?:(?:export|extern)\s+)?(?:(?:inline|noinline)\s+)?fn\s+(" + NAME + r")\s*\(")
RAW_FN_NAME_RE = re.compile(r'\bfn\s+([A-Za-z_]\w*|@"(?:\\.|[^"\\])*")\s*\(')
CONTAINER_RE = re.compile(r"^\s*(?:pub\s+)?(?:const|var)\s+(" + NAME + r")\s*(?::[^=]*)?=\s*"
                          r"(?:(?:extern|packed)\s+)?(?:struct|union|enum|opaque)\b")
RAW_CONTAINER_NAME_RE = re.compile(r'\b(?:const|var)\s+([A-Za-z_]\w*|@"(?:\\.|[^"\\])*")')
TEST_RE = re.compile(r"^\s*test\b.*\{\s*$")
IMPORT_RE = re.compile(r'^\s*(?:pub\s+)?const\s+(\w+)\s*=\s*@import\("([\w./]+\.zig)"\)')
CALL_RE = re.compile(r"(?:(\b\w+)\.)?\b([A-Za-z_]\w*)\s*\(")
ASSERT_RE = re.compile(r"\bassert\s*\(")
ASSERT_PRIMITIVE = "assert"
LINE_RULES = [
    ("R2", re.compile(r"\bwhile\s*\(\s*true\s*\)"), "unbounded loop `while (true)`"),
    ("R9", re.compile(r"\*\s*const\s+fn\b|\*\s*fn\s*\("), "function pointer type"),
]
# These rules read the whole file, so a match can span lines. The finding
# goes on the line where the match starts.
TEXT_RULES = [
    ("R7", re.compile(r"\bcatch\s*\{\s*\}"), "swallowed error `catch {}`"),
    ("R7", re.compile(r"\belse\s*\|_\|\s*\{\s*\}"), "swallowed error `else |_| {}`"),
    ("R7", re.compile(r"\bcatch\s+unreachable\b"), "`catch unreachable` hides an error"),
]
# A discarded call result: `_ = f()`, `_, x = f()`, or `const a, _ = f()`.
# The call must be the whole right side, see whole_call.
CALLEE = r"\s*(?:try\s+)?(?:@This\(\)\.)?[\w.]+\s*\("
DISCARD_RES = [
    re.compile(r"(?<![\w.,])(?<!,\s)_\s*(?:,[^=;]*)?(?<![=!<>])=(?!=)" + CALLEE),
    re.compile(r"\b(?:const|var)\s+[^=;]*,\s*_\s*(?:,[^=;]*)?(?<![=!<>])=(?!=)" + CALLEE),
]
KEYWORDS = {"if", "while", "for", "switch", "return", "catch", "fn", "try", "orelse", "and", "or"}


def strip_code(line):
    """Remove comments, string literals and char literals from one line."""
    s = line.lstrip()
    if s.startswith("\\\\"):
        return ""
    line = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    line = re.sub(r"'(?:\\.|[^'\\])+'", "''", line)
    return line.split("//", 1)[0]


def suppressed(lines, idx, rule):
    tag = f"nasa-lint: allow({rule})"
    return tag in lines[idx] or (idx > 0 and tag in lines[idx - 1])


def block_end(code, start):
    """Return the index of the line that closes the block opened on line `start`."""
    depth = 0
    for i in range(start, len(code)):
        depth += code[i].count("{") - code[i].count("}")
        if depth <= 0 and i > start:
            return i
        if depth <= 0 and code[i].rstrip().endswith("}") and code[i].count("{") > 0:
            return i
    return len(code) - 1


def body_end(code, open_idx):
    """Return the line that closes the body that opens with the last `{` on
    line `open_idx`. A brace before it, as in `}) void {` after a
    `struct {` parameter, does not count."""
    first = code[open_idx]
    depth = 1 + first[first.rfind("{") + 1:].count("{") - first[first.rfind("{") + 1:].count("}")
    if depth <= 0:
        return open_idx
    for i in range(open_idx + 1, len(code)):
        depth += code[i].count("{") - code[i].count("}")
        if depth <= 0:
            return i
    return len(code) - 1


def body_open(code, fn_idx, col):
    """Find the line where the body of the fn on `fn_idx` opens.
    `col` is the column of the `(` of the parameter list. The body opens on
    the first line that ends with `{` when the parentheses are balanced. A
    one-line function `fn f() void {}` opens and closes on its own line."""
    depth, after_params = 0, False
    for i in range(fn_idx, min(fn_idx + MAX_SIGNATURE_LINES, len(code))):
        text = code[i][col:] if i == fn_idx else code[i]
        braces = 0
        for ch in text:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                after_params = after_params or depth == 0
            elif ch == "{" and depth == 0:
                braces += 1
            elif ch == "}" and depth == 0:
                braces -= 1
        s = text.rstrip()
        if depth == 0 and after_params and s.endswith("{"):
            return i
        if depth == 0 and after_params and s.endswith("}") and braces == 0 and "{" in text:
            return i
        if depth == 0 and after_params and s.endswith(";"):
            return None
    return None


def whole_call(code, start):
    """Report whether the call that opens at code[start] is the whole value:
    `f()`, `a.f().g()`, `f() catch x` or `f().?`, but not `f().field` or
    `f()[0]`. A call that does not close on its line counts as whole."""
    i = start
    for _ in range(len(code)):
        depth, j = 0, i
        while j < len(code):
            depth += {"(": 1, ")": -1}.get(code[j], 0)
            if depth == 0:
                break
            j += 1
        if j >= len(code):
            return True
        rest = code[j + 1:]
        nxt = re.match(r"\s*\.\s*\w+\s*\(", rest)
        if nxt:
            i = j + nxt.end() - 1
            continue
        return not re.match(r"\s*(?:\.\s*\w|\[)", rest)
    return True


def is_test_helper(name):
    return name.startswith("test") or name.endswith("Test")


def raw_name(rx, line, fallback):
    """Return the name that rx finds in the raw line: a quoted name keeps its text."""
    m = rx.search(line)
    return m.group(1) if m else fallback


def scan_file(path, root):
    lines = path.read_text(encoding="utf-8").split("\n")
    code = [strip_code(l) for l in lines]
    rel = path.relative_to(root).as_posix()
    test_lines = set()
    for i, c in enumerate(code):
        if TEST_RE.match(c) and i not in test_lines:
            test_lines.update(range(i, block_end(code, i) + 1))
    imports = {m.group(1): m.group(2) for m in map(IMPORT_RE.match, lines) if m}
    scopes, fns = [], []
    for i, c in enumerate(code):
        if i in test_lines:
            continue
        m = CONTAINER_RE.match(c)
        if m and "{" in c:
            name = raw_name(RAW_CONTAINER_NAME_RE, lines[i], m.group(1))
            scopes.append({"seg": name, "start": i, "end": block_end(code, i)})
        m = FN_RE.match(c)
        if not m:
            continue
        open_idx = body_open(code, i, m.end() - 1)
        if open_idx is None:
            continue
        name = raw_name(RAW_FN_NAME_RE, lines[i], m.group(1))
        end = open_idx if open_idx == i and code[i].rstrip().endswith("}") else body_end(code, open_idx)
        fn = {"name": name, "start": i, "end": end, "helper": is_test_helper(name)}
        fns.append(fn)
        scopes.append({"seg": name + "()", "start": i, "end": end, "fn": fn})
    for fn in fns:
        outer = [s for s in scopes if s["start"] < fn["start"] <= s["end"] and s.get("fn") is not fn]
        fn["scope"] = [s["seg"] for s in sorted(outer, key=lambda s: s["start"])]
        fn["key"] = ".".join(fn["scope"] + [fn["name"]])
        fn["lines"] = []
    # A function that starts later is inner, so it takes its lines from the outer one.
    owner = {}
    for fn in sorted(fns, key=lambda f: f["start"]):
        for i in range(fn["start"], fn["end"] + 1):
            owner[i] = fn
    for i in sorted(owner):
        if i not in test_lines:
            owner[i]["lines"].append(i)
    return {"path": path, "rel": rel, "lines": lines, "code": code, "test_lines": test_lines,
            "imports": imports, "fns": fns}


def call_matches(line):
    """Yield (qualifier, name) for each call on a stripped line. A builtin
    `@f(`, a decl literal `.f(`, a method call on an expression `x().f(` and
    the name of a nested `fn f(` give no call. `@This().f(` has the
    qualifier `@This`."""
    for m in CALL_RE.finditer(line):
        qual, name = m.group(1), m.group(2)
        before = line[:m.start()]
        if name in KEYWORDS or re.search(r"\bfn\s+$", before):
            continue
        if qual is None and before.endswith("@This()."):
            qual = "@This"
        elif qual is None and (before.endswith("@") or before.rstrip().endswith(".")):
            continue
        yield qual, name


def calls_of(fn, f, nodes):
    """Return the node keys that the calls of fn reach."""
    edges = set()
    for i in fn["lines"]:
        for qual, name in call_matches(f["code"][i]):
            if qual is None or qual in ("self", "Self", "@This"):
                lowest = 0 if qual is None else len(fn["scope"])
                for depth in range(len(fn["scope"]), lowest - 1, -1):
                    key = (f["rel"], ".".join(fn["scope"][:depth] + [name]))
                    if key in nodes:
                        edges.add(key)
                        break
            elif qual in f["imports"]:
                target = posixpath.normpath(posixpath.join(posixpath.dirname(f["rel"]), f["imports"][qual]))
                edges.add((target, name))
    return edges


def assertions_of(fn, f):
    n = 0
    for i in fn["lines"]:
        for m in ASSERT_RE.finditer(f["code"][i]):
            if not re.search(r"\bfn\s+$", f["code"][i][:m.start()]):
                n += 1
    return n


def find_cycles(graph):
    """Iterative three-color DFS. Return each back edge as a cycle path."""
    color, cycles = {}, []
    for root in sorted(graph):
        if color.get(root):
            continue
        stack = [(root, iter(sorted(graph[root])))]
        path = [root]
        color[root] = 1
        while stack:
            node, it = stack[-1]
            nxt = next(it, None)
            if nxt is None:
                color[node] = 2
                stack.pop()
                path.pop()
                continue
            if nxt not in graph:
                continue
            if color.get(nxt) == 1:
                cycles.append(path[path.index(nxt):] + [nxt])
            elif not color.get(nxt):
                color[nxt] = 1
                stack.append((nxt, iter(sorted(graph[nxt]))))
                path.append(nxt)
    return cycles


def line_findings(f, err):
    lines, code, test_lines = f["lines"], f["code"], f["test_lines"]
    for i, c in enumerate(code):
        if i in test_lines:
            continue
        for rule, rx, msg in LINE_RULES:
            if rx.search(c) and not suppressed(lines, i, rule):
                err(f, i, rule, msg)
        for rx in DISCARD_RES:
            m = rx.search(c)
            if m and whole_call(c, m.end() - 1) and not suppressed(lines, i, "R7"):
                err(f, i, "R7", "discarded call result `_ = f(...)`")
                break
    text = "\n".join(code)
    for rule, rx, msg in TEXT_RULES:
        for m in rx.finditer(text):
            i = text.count("\n", 0, m.start())
            if i not in test_lines and not suppressed(lines, i, rule):
                err(f, i, rule, msg)


def main():
    root = pathlib.Path.cwd()
    errors, total_fns, total_asserts = [], 0, 0
    graph, where = {}, {}
    verbose = "--verbose" in sys.argv[1:]

    def err(f, line, rule, msg):
        errors.append(f"{f['rel']}:{line + 1}: {rule}: {msg}")

    files = [scan_file(p, root) for p in sorted((root / "src").rglob("*.zig"))]
    for f in files:
        for fn in f["fns"]:
            if not fn["helper"]:
                where.setdefault((f["rel"], fn["key"]), (f, fn))
    for f in files:
        line_findings(f, err)
        for fn in f["fns"]:
            if fn["helper"]:
                continue
            if fn["name"] != ASSERT_PRIMITIVE:
                total_fns += 1
                n_asserts = assertions_of(fn, f)
                total_asserts += n_asserts
                if verbose and n_asserts < MIN_ASSERT_AVG:
                    print(f"{f['rel']}:{fn['start'] + 1}: info: fn {fn['name']} has {n_asserts} assertion(s)")
            length = fn["end"] - fn["start"] + 1
            if length > MAX_FN_LINES and not suppressed(f["lines"], fn["start"], "R4"):
                err(f, fn["start"], "R4", f"fn {fn['name']} has {length} lines (max {MAX_FN_LINES})")
            graph.setdefault((f["rel"], fn["key"]), set()).update(calls_of(fn, f, where))
    for cyc in find_cycles(graph):
        f, fn = where[cyc[0]]
        if not suppressed(f["lines"], fn["start"], "R1"):
            chain = " -> ".join(f"{rel}:{key}" for rel, key in cyc)
            err(f, fn["start"], "R1", f"recursion: {chain}")
    avg = total_asserts / total_fns if total_fns else 0.0
    if total_fns and avg < MIN_ASSERT_AVG:
        errors.append(f"src: R5: {total_asserts} assertions in {total_fns} functions "
                      f"(average {avg:.2f}, min {MIN_ASSERT_AVG})")
    for e in errors:
        print(e)
    print(f"nasa-lint: {len(errors)} error(s); {total_fns} functions, "
          f"{total_asserts} assertions (average {avg:.2f})")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
