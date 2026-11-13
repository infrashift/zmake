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
"""
import pathlib
import re
import sys

MAX_FN_LINES = 60
MIN_ASSERT_AVG = 2.0

FN_RE = re.compile(r"^\s*(?:pub\s+)?(?:export\s+)?(?:inline\s+)?fn\s+([A-Za-z_]\w*)\s*\(")
TEST_RE = re.compile(r"^\s*test\b.*\{\s*$")
IMPORT_RE = re.compile(r'^\s*(?:pub\s+)?const\s+(\w+)\s*=\s*@import\("([\w./]+\.zig)"\)')
CALL_RE = re.compile(r"(?:(\b\w+)\.)?\b([A-Za-z_]\w*)\s*\(")
ASSERT_RE = re.compile(r"\bassert\s*\(")
LINE_RULES = [
    ("R2", re.compile(r"\bwhile\s*\(\s*true\s*\)"), "unbounded loop `while (true)`"),
    ("R7", re.compile(r"\bcatch\s*\{\s*\}"), "swallowed error `catch {}`"),
    ("R7", re.compile(r"\belse\s*\|_\|\s*\{\s*\}"), "swallowed error `else |_| {}`"),
    ("R7", re.compile(r"\bcatch\s+unreachable\b"), "`catch unreachable` hides an error"),
    ("R7", re.compile(r"(?<![\w.])_\s*=\s*(?:try\s+)?[\w.]+\s*\("), "discarded call result `_ = f(...)`"),
    ("R9", re.compile(r"\*\s*const\s+fn\b|\*\s*fn\s*\("), "function pointer type"),
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


def body_open(code, fn_idx):
    """Find the line where the body of the fn on `fn_idx` opens (`{` at line end)."""
    for i in range(fn_idx, min(fn_idx + 20, len(code))):
        if code[i].rstrip().endswith("{"):
            return i
        if code[i].rstrip().endswith(";"):
            return None
    return None


def scan_file(path):
    lines = path.read_text(encoding="utf-8").split("\n")
    code = [strip_code(l) for l in lines]
    test_lines = set()
    for i, c in enumerate(code):
        if TEST_RE.match(c) and i not in test_lines:
            test_lines.update(range(i, block_end(code, i) + 1))
    imports = {m.group(1): m.group(2) for m in map(IMPORT_RE.match, lines) if m}
    fns = []
    for i, c in enumerate(code):
        m = FN_RE.match(c)
        if not m or i in test_lines or is_test_helper(m.group(1)):
            continue
        open_idx = body_open(code, i)
        if open_idx is None:
            continue
        end = block_end(code, open_idx)
        fns.append({"name": m.group(1), "start": i, "end": end, "body": code[open_idx + 1:end]})
    return lines, code, test_lines, imports, fns


def is_test_helper(name):
    return name.startswith("test") or name.endswith("Test")


def calls_of(fn, imports, local_names, file_name):
    edges = set()
    for c in fn["body"]:
        for m in CALL_RE.finditer(c):
            qual, name = m.group(1), m.group(2)
            if name in KEYWORDS:
                continue
            if qual is None or qual in ("self", "Self", "@This"):
                if name in local_names:
                    edges.add((file_name, name))
            elif qual in imports:
                edges.add((imports[qual], name))
    return edges


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


def main():
    root = pathlib.Path.cwd()
    errors, total_fns, total_asserts = [], 0, 0
    graph, where = {}, {}
    verbose = "--verbose" in sys.argv[1:]

    def err(path, line, rule, msg):
        errors.append(f"{path.relative_to(root)}:{line + 1}: {rule}: {msg}")

    for path in sorted((root / "src").rglob("*.zig")):
        lines, code, test_lines, imports, fns = scan_file(path)
        for i, c in enumerate(code):
            if i in test_lines:
                continue
            for rule, rx, msg in LINE_RULES:
                if rx.search(c) and not suppressed(lines, i, rule):
                    err(path, i, rule, msg)
        local = {f["name"] for f in fns}
        for f in fns:
            total_fns += 1
            n_asserts = sum(len(ASSERT_RE.findall(c)) for c in f["body"])
            total_asserts += n_asserts
            if verbose and n_asserts < MIN_ASSERT_AVG:
                print(f"{path.relative_to(root)}:{f['start'] + 1}: info: fn {f['name']} has {n_asserts} assertion(s)")
            length = f["end"] - f["start"] + 1
            if length > MAX_FN_LINES and not suppressed(lines, f["start"], "R4"):
                err(path, f["start"], "R4", f"fn {f['name']} has {length} lines (max {MAX_FN_LINES})")
            key = (path.name, f["name"])
            graph.setdefault(key, set()).update(calls_of(f, imports, local, path.name))
            where[key] = (path, f["start"], lines)
    for cyc in find_cycles(graph):
        path, line, lines = where[cyc[0]]
        if not suppressed(lines, line, "R1"):
            chain = " -> ".join(f"{fname}:{name}" for fname, name in cyc)
            err(path, line, "R1", f"recursion: {chain}")
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
