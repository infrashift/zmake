//! Two-phase variable evaluator.
//!
//! - `load` replays the statements of the input file in order. It expands `:=`
//!   values, target names and prerequisite lists at once (immediate phase).
//! - `expand` expands `=` values and recipe lines on demand (deferred phase).
//!
//! Make expansion nests: a value can refer to a variable whose value refers to
//! another variable. ADR-0003 forbids recursion, so `expand` keeps an explicit
//! stack of frames. Each frame expands one string. A frame that waits for the
//! arguments of a reference or a function has a `pending` call and a child frame
//! above it. When a child frame ends, `deliver` hands its result to the parent.

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const ast = @import("ast.zig");
const fns = @import("functions.zig");
const parser = @import("parser.zig");
const Diagnostic = @import("diag.zig").Diagnostic;

pub const Error = error{ Eval, OutOfMemory };

/// The automatic variables of one recipe.
pub const Auto = struct {
    target: []const u8,
    /// All prerequisites in order, with duplicates (`$+`).
    prerequisites: []const []const u8,
    stem: []const u8,
    /// The prerequisites newer than the target (`$?`).
    newer: []const []const u8,
};

pub const VarTable = std.StringHashMapUnmanaged(ast.Variable);

const Func = enum { ref, subst_ref, subst, patsubst, wildcard, shell };

const Pending = struct {
    func: Func,
    n: u8,
    next: u8 = 0,
    raw: [3][]const u8 = .{ "", "", "" },
    results: [3][]const u8 = .{ "", "", "" },
};

const Frame = struct {
    src: []const u8,
    pos: usize = 0,
    out: std.ArrayList(u8) = .empty,
    pending: ?Pending = null,
    /// Set when the frame expands the value of a recursive variable.
    var_name: ?[]const u8 = null,
    /// A substitution reference (`$(X:a=b)`) to apply to the result.
    subst: ?[2][]const u8 = null,
};

const Stack = struct {
    frames: [ast.limits.expansion_depth_max]Frame = undefined,
    len: usize = 0,

    fn top(s: *Stack) *Frame {
        assert(s.len > 0 and s.len <= s.frames.len);
        const f = &s.frames[s.len - 1];
        assert(f.pos <= f.src.len);
        return f;
    }
};

/// GNU Make functions that zmake does not implement (ADR-0005). zmake rejects
/// them, so `$(foreach ...)` does not expand to an empty variable by mistake.
const unsupported_functions = [_][]const u8{
    "abspath", "addprefix", "addsuffix", "and",        "basename",   "call",      "dir",    "error",
    "eval",    "file",      "filter",    "filter-out", "findstring", "firstword", "flavor", "foreach",
    "guile",   "if",        "info",      "intcmp",     "join",       "lastword",  "let",    "notdir",
    "or",      "origin",    "realpath",  "sort",       "strip",      "suffix",    "value",  "warning",
    "word",    "wordlist",  "words",
};

pub const Evaluator = struct {
    arena: std.mem.Allocator,
    io: Io,
    /// The directory for `$(wildcard ...)`.
    dir: Io.Dir,
    diag: *Diagnostic,
    vars: VarTable = .empty,
    /// The location for error messages.
    filename: []const u8 = "zmake",
    line: u32 = 0,

    pub fn init(arena: std.mem.Allocator, io: Io, dir: Io.Dir, diag: *Diagnostic) Evaluator {
        assert(diag.len <= Diagnostic.capacity);
        const ev: Evaluator = .{ .arena = arena, .io = io, .dir = dir, .diag = diag };
        assert(ev.vars.count() == 0);
        return ev;
    }

    /// Define a variable unless a definition with a higher origin exists.
    pub fn define(ev: *Evaluator, name: []const u8, value: []const u8, recursive: bool, origin: ast.Origin) Error!void {
        assert(name.len > 0);
        if (ev.vars.get(name)) |old| {
            if (@backingInt(old.origin) > @backingInt(origin)) return;
        }
        try ev.vars.put(ev.arena, name, .{ .value = value, .recursive = recursive, .origin = origin });
        assert(ev.vars.contains(name));
    }

    pub fn lookup(ev: *const Evaluator, name: []const u8) ?ast.Variable {
        assert(name.len > 0);
        return ev.vars.get(name);
    }

    /// Set `MAKE` and `SHELL`. GNU Make ignores `SHELL` from the environment.
    pub fn defineDefaults(ev: *Evaluator, make_path: []const u8) Error!void {
        assert(make_path.len > 0);
        try ev.define("MAKE", make_path, false, .default);
        try ev.define("SHELL", "/bin/sh", false, .default);
        assert(ev.vars.count() >= 2);
    }

    /// Import the environment as recursive variables, except `SHELL`.
    pub fn importEnvironment(ev: *Evaluator, env: *const std.process.Environ.Map) Error!void {
        var it = env.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            if (name.len == 0 or std.mem.eql(u8, name, "SHELL")) continue;
            assert(name.len > 0);
            try ev.define(name, entry.value_ptr.*, true, .environment);
        }
        assert(ev.vars.count() >= env.count() -| 1);
    }

    pub fn fail(ev: *Evaluator, comptime fmt: []const u8, args: anytype) Error {
        comptime assert(fmt.len > 0);
        var buf: [Diagnostic.capacity]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch "error";
        if (ev.line > 0) {
            ev.diag.set("{s}:{d}: *** {s}.  Stop.", .{ ev.filename, ev.line, msg });
        } else {
            ev.diag.set("*** {s}.  Stop.", .{msg});
        }
        assert(ev.diag.len > 0);
        return error.Eval;
    }

    /// Expand `text`. `auto` holds the automatic variables of a recipe, or null.
    pub fn expand(ev: *Evaluator, text: []const u8, auto: ?*const Auto) Error![]const u8 {
        if (std.mem.indexOfScalar(u8, text, '$') == null) return text;
        var stack: Stack = .{};
        try ev.push(&stack, .{ .src = text });
        var steps: u32 = 0;
        while (steps < ast.limits.expansion_steps_max) : (steps += 1) {
            assert(stack.len >= 1);
            const top = stack.top();
            assert(top.pending == null);
            if (top.pos < top.src.len) {
                try ev.scan(&stack, auto);
                continue;
            }
            const result = try ev.finish(top);
            stack.len -= 1;
            if (stack.len == 0) {
                assert(result.len <= ast.limits.expansion_bytes_max);
                return result;
            }
            try ev.deliver(&stack, result, auto);
        }
        return ev.fail("expansion takes more than {d} steps", .{ast.limits.expansion_steps_max});
    }

    fn push(ev: *Evaluator, stack: *Stack, frame: Frame) Error!void {
        assert(stack.len <= stack.frames.len);
        if (stack.len == stack.frames.len) {
            return ev.fail("variable references nest more than {d} levels", .{ast.limits.expansion_depth_max});
        }
        stack.frames[stack.len] = frame;
        stack.len += 1;
        assert(stack.top().pos == 0);
    }

    /// End a frame: apply its substitution reference and return the text.
    fn finish(ev: *Evaluator, frame: *Frame) Error![]const u8 {
        assert(frame.pos == frame.src.len and frame.pending == null);
        const sub = frame.subst orelse return frame.out.items;
        const result = try fns.substRef(ev.arena, sub[0], sub[1], frame.out.items);
        assert(frame.var_name != null);
        return result;
    }

    /// Give the result of the frame that ended to its parent, the new top.
    fn deliver(ev: *Evaluator, stack: *Stack, result: []const u8, auto: ?*const Auto) Error!void {
        assert(stack.len >= 1);
        const parent = &stack.frames[stack.len - 1];
        if (parent.pending) |*p| {
            assert(p.next < p.n);
            p.results[p.next] = result;
            p.next += 1;
            if (p.next < p.n) return ev.push(stack, .{ .src = p.raw[p.next] });
            const done = p.*;
            parent.pending = null;
            return ev.complete(stack, done, auto);
        }
        try ev.emit(parent, result);
        assert(parent.pending == null);
    }

    fn emit(ev: *Evaluator, frame: *Frame, text: []const u8) Error!void {
        assert(frame.pos <= frame.src.len);
        try frame.out.appendSlice(ev.arena, text);
        if (frame.out.items.len > ast.limits.expansion_bytes_max) {
            return ev.fail("expansion is longer than {d} bytes", .{ast.limits.expansion_bytes_max});
        }
        assert(frame.out.items.len >= text.len);
    }

    /// Copy literal text up to the next `$`, then start one reference.
    fn scan(ev: *Evaluator, stack: *Stack, auto: ?*const Auto) Error!void {
        const top = stack.top();
        const rest = top.src[top.pos..];
        assert(rest.len > 0);
        const dollar = std.mem.indexOfScalar(u8, rest, '$') orelse rest.len;
        try ev.emit(top, rest[0..dollar]);
        top.pos += dollar;
        if (top.pos >= top.src.len) return;
        if (top.pos + 1 == top.src.len) {
            top.pos += 1; // A `$` at the end expands to nothing.
            return;
        }
        const c = top.src[top.pos + 1];
        if (c == '$') {
            try ev.emit(top, "$");
            top.pos += 2;
        } else if (c == '(' or c == '{') {
            const close = matchingClose(top.src, top.pos + 1) orelse {
                return ev.fail("unterminated variable reference", .{});
            };
            const inner = top.src[top.pos + 2 .. close];
            top.pos = close + 1;
            try ev.startReference(stack, inner, auto);
        } else {
            top.pos += 2;
            try ev.lookupAndPush(stack, top.src[top.pos - 1 .. top.pos], null, auto);
        }
        assert(top.pos <= top.src.len);
    }

    /// Start `$(inner)`: a function call, a substitution reference or a variable.
    fn startReference(ev: *Evaluator, stack: *Stack, inner: []const u8, auto: ?*const Auto) Error!void {
        assert(stack.len > 0);
        const pending = try ev.classifyReference(inner);
        assert(pending.n >= 1 and pending.n <= 3);
        if (pending.func == .ref and std.mem.indexOfScalar(u8, inner, '$') == null) {
            return ev.lookupAndPush(stack, inner, null, auto);
        }
        stack.top().pending = pending;
        try ev.push(stack, .{ .src = pending.raw[0] });
    }

    fn classifyReference(ev: *Evaluator, inner: []const u8) Error!Pending {
        const word_end = std.mem.indexOfAny(u8, inner, " \t") orelse inner.len;
        const word = inner[0..word_end];
        const args = std.mem.trimStart(u8, inner[word_end..], " \t");
        if (word_end < inner.len) {
            const func_arity = [_]struct { Func, []const u8, u8 }{
                .{ .subst, "subst", 3 },       .{ .patsubst, "patsubst", 3 },
                .{ .wildcard, "wildcard", 1 }, .{ .shell, "shell", 1 },
            };
            for (func_arity) |f| {
                if (std.mem.eql(u8, word, f[1])) return ev.splitArgs(f[0], f[1], args, f[2]);
            }
            for (unsupported_functions) |name| {
                if (std.mem.eql(u8, word, name)) return ev.fail("unsupported function '{s}'", .{name});
            }
        }
        if (parser.findTopLevel(inner, ":")) |colon| {
            const tail = inner[colon + 1 ..];
            if (parser.findTopLevel(tail, "=")) |eq| {
                assert(colon + 1 + eq < inner.len);
                return .{ .func = .subst_ref, .n = 3, .raw = .{ inner[0..colon], tail[0..eq], tail[eq + 1 ..] } };
            }
        }
        assert(word.len <= inner.len);
        return .{ .func = .ref, .n = 1, .raw = .{ inner, "", "" } };
    }

    /// Split function arguments at top-level commas. The last argument keeps the rest.
    fn splitArgs(ev: *Evaluator, func: Func, name: []const u8, args: []const u8, n: u8) Error!Pending {
        assert(n >= 1 and n <= 3);
        var p: Pending = .{ .func = func, .n = n };
        var rest = args;
        var i: u8 = 0;
        while (i + 1 < n) : (i += 1) {
            const comma = topLevelComma(rest) orelse {
                return ev.fail("insufficient number of arguments ({d}) to function '{s}'", .{ i + 1, name });
            };
            p.raw[i] = rest[0..comma];
            rest = rest[comma + 1 ..];
        }
        p.raw[n - 1] = rest;
        assert(i == n - 1);
        return p;
    }

    /// All arguments of a pending call have a value. Apply the call.
    fn complete(ev: *Evaluator, stack: *Stack, p: Pending, auto: ?*const Auto) Error!void {
        assert(p.next == p.n);
        assert(stack.len >= 1);
        const r = p.results;
        const top = stack.top();
        const a = ev.arena;
        const ws = fns.whitespace;
        const text: []const u8 = switch (p.func) {
            .ref => return ev.lookupAndPush(stack, std.mem.trim(u8, r[0], ws), null, auto),
            .subst_ref => return ev.lookupAndPush(stack, std.mem.trim(u8, r[0], ws), .{ r[1], r[2] }, auto),
            .subst => try fns.subst(a, r[0], r[1], r[2]),
            .patsubst => try fns.patsubst(a, std.mem.trim(u8, r[0], ws), std.mem.trim(u8, r[1], ws), r[2]),
            .wildcard => fns.wildcard(a, ev.io, ev.dir, r[0]) catch |err| return ev.functionError("wildcard", err),
            .shell => blk: {
                const sh = if (ev.lookup("SHELL")) |v| v.value else "/bin/sh";
                break :blk fns.shell(a, ev.io, sh, r[0]) catch |err| return ev.functionError("shell", err);
            },
        };
        try ev.emit(top, text);
        assert(top.pending == null);
    }

    fn functionError(ev: *Evaluator, name: []const u8, err: fns.Error) Error {
        assert(name.len > 0);
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => ev.fail("function '{s}' failed: {s}", .{ name, @errorName(err) }),
        };
    }

    /// Emit the value of variable `name`. A recursive value needs a new frame.
    fn lookupAndPush(ev: *Evaluator, stack: *Stack, name: []const u8, sub: ?[2][]const u8, auto: ?*const Auto) Error!void {
        assert(stack.len > 0);
        const top = stack.top();
        if (name.len == 0) return;
        if (try ev.autoValue(name, auto)) |value| {
            return ev.emit(top, if (sub) |s| try fns.substRef(ev.arena, s[0], s[1], value) else value);
        }
        const v = ev.lookup(name) orelse return;
        if (!v.recursive) {
            return ev.emit(top, if (sub) |s| try fns.substRef(ev.arena, s[0], s[1], v.value) else v.value);
        }
        for (stack.frames[0..stack.len]) |f| {
            const active = f.var_name orelse continue;
            if (std.mem.eql(u8, active, name)) {
                return ev.fail("Recursive variable '{s}' references itself (eventually)", .{name});
            }
        }
        try ev.push(stack, .{ .src = v.value, .var_name = name, .subst = sub });
        assert(stack.top().var_name != null);
    }

    /// Return the value of an automatic variable, or null when `name` is not one.
    fn autoValue(ev: *Evaluator, name: []const u8, auto: ?*const Auto) Error!?[]const u8 {
        assert(name.len > 0);
        if (name.len > 2 or std.mem.indexOfScalar(u8, "@<^+*?", name[0]) == null) return null;
        if (name.len == 2 and name[1] != 'D' and name[1] != 'F') return null;
        const a = auto orelse return "";
        const raw: []const u8 = switch (name[0]) {
            '@' => a.target,
            '<' => if (a.prerequisites.len > 0) a.prerequisites[0] else "",
            '^' => try joinWords(ev.arena, a.prerequisites, true),
            '+' => try joinWords(ev.arena, a.prerequisites, false),
            '*' => a.stem,
            '?' => try joinWords(ev.arena, a.newer, true),
            else => unreachable,
        };
        if (name.len == 1) return raw;
        assert(name.len == 2);
        return try fns.dirOrFile(ev.arena, raw, name[1]);
    }
};

/// Join words with one space. With `dedupe`, keep the first occurrence only.
fn joinWords(arena: std.mem.Allocator, words: []const []const u8, dedupe: bool) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (words, 0..) |w, i| {
        assert(w.len > 0);
        if (dedupe) {
            const seen = for (words[0..i]) |prev| {
                if (std.mem.eql(u8, prev, w)) break true;
            } else false;
            if (seen) continue;
        }
        try fns.appendWord(arena, &out, w);
    }
    assert(words.len == 0 or out.items.len > 0);
    return out.items;
}

/// Return the index of the `)` or `}` that closes the opener at `open`. Count
/// only the opener's own bracket type, as GNU Make does.
fn matchingClose(src: []const u8, open: usize) ?usize {
    assert(src[open] == '(' or src[open] == '{');
    const opener = src[open];
    const closer: u8 = if (opener == '(') ')' else '}';
    var depth: usize = 0;
    var i = open;
    while (i < src.len) : (i += 1) {
        if (src[i] == opener) depth += 1;
        if (src[i] == closer) {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    assert(depth > 0);
    return null;
}

/// Return the index of the first comma outside parentheses and braces.
fn topLevelComma(s: []const u8) ?usize {
    var depth: usize = 0;
    for (s, 0..) |c, i| {
        switch (c) {
            '(', '{' => depth += 1,
            ')', '}' => depth -|= 1,
            ',' => if (depth == 0) {
                assert(i < s.len);
                return i;
            },
            else => {},
        }
    }
    return null;
}

const testing = std.testing;

fn testEvaluator(arena: std.mem.Allocator, diag: *Diagnostic) Evaluator {
    return Evaluator.init(arena, testing.io, std.Io.Dir.cwd(), diag);
}

test "expand plain, braces, single-char and escaped references" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("A", "1", false, .file);
    try ev.define("X", "x", false, .file);
    try testing.expectEqualStrings("1-1-x-$-", try ev.expand("$(A)-${A}-$X-$$-$(NOPE)", null));
}

test "recursive values expand at use time; simple values at definition" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("B", "$(C) b", true, .file);
    try ev.define("C", "c", false, .file);
    try testing.expectEqualStrings("c b", try ev.expand("$(B)", null));
    try ev.define("C", "C2", false, .file);
    try testing.expectEqualStrings("C2 b", try ev.expand("$(B)", null));
}

test "computed names and substitution references" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("SRC", "a.c b.c", false, .file);
    try ev.define("WHICH", "SRC", false, .file);
    try ev.define("EXT", ".o", false, .file);
    try testing.expectEqualStrings("a.c b.c", try ev.expand("$($(WHICH))", null));
    try testing.expectEqualStrings("a.o b.o", try ev.expand("$(SRC:.c=.o)", null));
    try testing.expectEqualStrings("out/a.o out/b.o", try ev.expand("$(SRC:%.c=out/%$(EXT))", null));
}

test "functions" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("SRC", "a.c b.c", false, .file);
    try testing.expectEqualStrings("a.o b.o", try ev.expand("$(patsubst %.c, %.o, $(SRC))", null));
    try testing.expectEqualStrings("a-c b-c", try ev.expand("$(subst .,-,$(SRC))", null));
    try testing.expectEqualStrings("hi there", try ev.expand("$(shell echo hi; echo there)", null));
    try testing.expectEqualStrings("x(y)", try ev.expand("$(subst a,(y),xa)", null));
}

test "automatic variables" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    const auto: Auto = .{
        .target = "out/app",
        .prerequisites = &.{ "src/a.o", "b.o", "src/a.o" },
        .stem = "app",
        .newer = &.{"b.o"},
    };
    const got = try ev.expand("$@ $< [$^] [$+] $* $? $(@D) $(@F) ${<D}", &auto);
    try testing.expectEqualStrings("out/app src/a.o [src/a.o b.o] [src/a.o b.o src/a.o] app b.o out app src", got);
    try testing.expectEqualStrings(" ", try ev.expand("$@ $<", null));
}

test "evaluation errors" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("LOOP", "x $(LOOP2)", true, .file);
    try ev.define("LOOP2", "$(LOOP)", true, .file);
    try testing.expectError(error.Eval, ev.expand("$(LOOP)", null));
    try testing.expectEqualStrings("*** Recursive variable 'LOOP' references itself (eventually).  Stop.", diag.message());
    try testing.expectError(error.Eval, ev.expand("$(foreach x,a b,$(x))", null));
    try testing.expectEqualStrings("*** unsupported function 'foreach'.  Stop.", diag.message());
    try testing.expectError(error.Eval, ev.expand("$(subst a,b)", null));
    try testing.expectError(error.Eval, ev.expand("$(A", null));
}

test "deep nesting fails at the depth limit" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    var text: std.ArrayList(u8) = .empty;
    for (0..ast.limits.expansion_depth_max + 1) |_| try text.appendSlice(arena.allocator(), "$(subst a,b,");
    try text.appendSlice(arena.allocator(), "a");
    for (0..ast.limits.expansion_depth_max + 1) |_| try text.append(arena.allocator(), ')');
    try testing.expectError(error.Eval, ev.expand(text.items, null));
}

test "origin precedence" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var ev = testEvaluator(arena.allocator(), &diag);
    try ev.define("CC", "clang", false, .command_line);
    try ev.define("CC", "gcc", false, .file);
    try testing.expectEqualStrings("clang", ev.lookup("CC").?.value);
    try ev.define("HOME", "/env", true, .environment);
    try ev.define("HOME", "/file", true, .file);
    try testing.expectEqualStrings("/file", ev.lookup("HOME").?.value);
}
