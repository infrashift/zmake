//! The reader. It reads the input file line by line and applies each statement
//! at once, so a conditional sees the variables defined above it. It handles
//! the conditionals (`ifeq`, `ifneq`, `ifdef`, `ifndef`, `else`, `endif`),
//! `define`, `override`, `undefine`, `include` and the texts of `$(eval ...)`.
//!
//! An explicit stack holds the open sources (the input file, the included
//! files and the eval texts), and another holds the open conditionals. Nothing here calls itself
//! (ADR-0003, rule R1). See ADR-0012.

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const eval = @import("eval.zig");
const database = @import("database.zig");
const fns = @import("functions.zig");
const Diagnostic = @import("diag.zig").Diagnostic;

pub const Error = error{ Syntax, Eval, OutOfMemory };

const ws = fns.whitespace;

/// `active`: this branch is in effect. `pending`: no branch so far. `done`: an
/// earlier branch was in effect. `ignored`: the conditional is inside a skipped branch.
const CondState = enum { active, pending, done, ignored };

const Cond = struct { state: CondState, seen_else: bool };

const Source = struct {
    lx: lexer.Lexer,
    /// The input file of the source. An eval text has the file of its caller.
    filename: []const u8,
    /// The number of open conditionals when the source started.
    cond_base: usize,
    /// A line to read again after the eval texts that it waits for.
    held: ?lexer.LogicalLine = null,
    /// False until the name of an input file is in `MAKEFILE_LIST`.
    listed: bool,
};

/// The first `include` file that does not exist. GNU Make reports it after it
/// reads all input.
const Missing = struct { name: []const u8, file: []const u8, line: u32 };

const conditional_words = [_][]const u8{ "ifeq", "ifneq", "ifdef", "ifndef", "else", "endif" };
const if_words = [_][]const u8{ "ifeq", "ifneq", "ifdef", "ifndef" };
const include_words = [_][]const u8{ "include", "-include", "sinclude" };
const reader_words = conditional_words ++ include_words ++ [_][]const u8{ "define", "endef", "override", "undefine" };

pub const Reader = struct {
    arena: std.mem.Allocator,
    ev: *eval.Evaluator,
    diag: *Diagnostic,
    mode: ast.SyntaxMode,
    /// The file of the top source, for messages.
    filename: []const u8,
    p: parser.Parser,
    b: database.Builder,
    /// The number of parser statements that the builder has applied.
    applied: usize = 0,
    conds: std.ArrayList(Cond) = .empty,
    sources: std.ArrayList(Source) = .empty,
    missing: ?Missing = null,

    fn fail(r: *Reader, line: u32, comptime fmt: []const u8, args: anytype) Error {
        assert(line > 0);
        var buf: [Diagnostic.capacity]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch "error";
        r.diag.set("{s}:{d}: *** {s}.  Stop.", .{ r.filename, line, msg });
        assert(r.diag.len > 0);
        return error.Syntax;
    }

    fn warn(r: *Reader, line: u32, comptime fmt: []const u8, args: anytype) void {
        assert(line > 0);
        var buf: [Diagnostic.capacity]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{s}:{d}: " ++ fmt ++ "\n", .{ r.filename, line } ++ args) catch return;
        assert(text.len > 0);
        Io.File.stderr().writeStreamingAll(r.ev.io, text) catch return;
    }

    /// True when every open conditional takes its current branch.
    fn active(r: *const Reader) bool {
        const n = r.conds.items.len;
        assert(n <= ast.limits.conditional_depth_max);
        if (n == 0) return true;
        const top = r.conds.items[n - 1];
        // A branch is in effect only inside a parent branch that is in effect.
        assert(top.state != .active or n == 1 or r.conds.items[n - 2].state == .active);
        return top.state == .active;
    }
};

/// Read `source` and return the rule database.
pub fn read(ev: *eval.Evaluator, source: []const u8, filename: []const u8, mode: ast.SyntaxMode, diag: *Diagnostic) Error!database.Database {
    assert(filename.len > 0);
    if (source.len > ast.limits.input_file_bytes_max) {
        diag.set("{s}: *** input file is larger than {d} bytes.  Stop.", .{ filename, ast.limits.input_file_bytes_max });
        return error.Syntax;
    }
    var r: Reader = .{
        .arena = ev.arena,
        .ev = ev,
        .diag = diag,
        .mode = mode,
        .filename = filename,
        .p = .{ .arena = ev.arena, .filename = filename, .mode = mode, .diag = diag },
        .b = .init(mode, filename),
    };
    ev.filename = filename;
    ev.reading = true;
    try pushSource(&r, source, 0, filename, false);
    try run(&r);
    ev.reading = false;
    assert(r.conds.items.len == 0 and r.sources.items.len == 0);
    if (r.missing) |m| return missingInclude(&r, m);
    return r.b.finish(ev);
}

fn pushSource(r: *Reader, text: []const u8, fixed_line: u32, filename: []const u8, listed: bool) Error!void {
    assert(filename.len > 0);
    if (r.sources.items.len >= ast.limits.source_depth_max) {
        return r.fail(@max(fixed_line, 1), "include files and eval texts nest more than {d} levels", .{ast.limits.source_depth_max});
    }
    var lx: lexer.Lexer = .init(r.arena, text, r.mode, filename);
    lx.fixed_line = fixed_line;
    try r.sources.append(r.arena, .{ .lx = lx, .filename = filename, .cond_base = r.conds.items.len, .listed = listed });
    assert(r.sources.items.len >= 1);
    assert(r.sources.items[r.sources.items.len - 1].lx.pos == 0);
}

/// Point the messages of the parser and the evaluator at the file of `src`.
/// Add an input file to `MAKEFILE_LIST` when zmake starts to read it.
fn enter(r: *Reader, src: *Source) Error!void {
    r.filename = src.filename;
    r.p.filename = src.filename;
    r.ev.filename = src.filename;
    if (src.listed) return;
    src.listed = true;
    const old = if (r.ev.lookup("MAKEFILE_LIST")) |v| v.value else "";
    const value = if (old.len == 0) src.filename else try std.mem.concat(r.arena, u8, &.{ old, " ", src.filename });
    try r.ev.define("MAKEFILE_LIST", value, false, .file);
    assert(src.listed);
    assert(r.ev.filename.len > 0);
}

fn run(r: *Reader) Error!void {
    assert(r.sources.items.len == 1);
    var budget: u32 = ast.limits.read_lines_max;
    while (r.sources.items.len > 0 and budget > 0) : (budget -= 1) {
        const src = &r.sources.items[r.sources.items.len - 1];
        try enter(r, src);
        const held = src.held;
        src.held = null;
        const ll = held orelse try src.lx.next(r.p.open_rule != null, r.diag) orelse {
            try endSource(r);
            continue;
        };
        try readLine(r, ll);
    }
    if (budget == 0) return r.fail(1, "more than {d} lines to read", .{ast.limits.read_lines_max});
    assert(r.sources.items.len == 0);
}

/// The source ends. Each conditional of the source must be closed.
fn endSource(r: *Reader) Error!void {
    var src = r.sources.pop().?;
    try enter(r, &src);
    assert(r.conds.items.len >= src.cond_base);
    if (r.conds.items.len > src.cond_base) return r.fail(src.lx.lastLine(), "missing 'endif'", .{});
    try r.p.closeRule();
    try applyNew(r);
    try pushEvals(r);
    assert(r.p.open_rule == null);
}

fn readLine(r: *Reader, ll: lexer.LogicalLine) Error!void {
    assert(ll.line > 0);
    if (ll.kind == .recipe) {
        if (r.active()) try r.p.feed(ll);
        return;
    }
    const word = parser.leadingDirective(ll.text, &reader_words);
    if (word) |w| {
        if (isAny(w, &conditional_words)) return conditional(r, w, ll);
    }
    if (!r.active()) return skipLine(r, ll, word);
    assert(r.active());
    // A statement ends the open rule. Its eval texts come before this line.
    if (r.p.open_rule != null) {
        try r.p.closeRule();
        try applyNew(r);
        if (r.ev.eval_queue.items.len > 0) {
            r.sources.items[r.sources.items.len - 1].held = ll;
            return pushEvals(r);
        }
    }
    if (word) |w| {
        try directive(r, w, ll);
    } else {
        try r.p.feed(ll);
        try applyNew(r);
    }
    try pushEvals(r);
}

/// In a skipped branch, only the body of `define` matters: an `endif` inside
/// it is text, not a directive.
fn skipLine(r: *Reader, ll: lexer.LogicalLine, word: ?[]const u8) Error!void {
    assert(!r.active());
    const w = word orelse return;
    const is_define = std.mem.eql(u8, w, "define") or
        (std.mem.eql(u8, w, "override") and parser.leadingDirective(rest(ll.text, w), &.{"define"}) != null);
    if (!is_define) return;
    const skipped = try defineBody(r, ll.line);
    assert(skipped.len <= ast.limits.input_file_bytes_max);
    assert(!r.active());
}

/// Apply the statements that the parser added since the last call.
fn applyNew(r: *Reader) Error!void {
    const items = r.p.statements.items;
    assert(r.applied <= items.len);
    while (r.applied < items.len) : (r.applied += 1) {
        const st = items[r.applied];
        switch (st) {
            .expression => |e| try expression(r, e),
            else => try r.b.apply(r.ev, st),
        }
    }
    assert(r.applied == r.p.statements.items.len);
}

/// A line without a separator. GNU Make reads a non-empty expansion again as
/// input text, so `$(RULE)` can define a rule.
fn expression(r: *Reader, e: ast.Expression) Error!void {
    assert(e.line > 0);
    r.ev.line = e.line;
    const value = try r.ev.expand(e.text, null);
    if (std.mem.trim(u8, value, ws).len == 0) return;
    try r.ev.eval_queue.append(r.arena, value);
    assert(r.ev.eval_queue.items.len > 0);
}

/// Read the queued eval texts as new sources, first text on top.
fn pushEvals(r: *Reader) Error!void {
    const queue = r.ev.eval_queue.items;
    if (queue.len == 0) return;
    assert(r.p.open_rule == null);
    const texts = try r.arena.dupe([]const u8, queue);
    r.ev.eval_queue.clearRetainingCapacity();
    var i = texts.len;
    while (i > 0) {
        i -= 1;
        try pushSource(r, texts[i], @max(r.ev.line, 1), r.filename, true);
    }
    assert(r.ev.eval_queue.items.len == 0);
}

fn directive(r: *Reader, word: []const u8, ll: lexer.LogicalLine) Error!void {
    assert(r.active() and r.p.open_rule == null);
    const eql = std.mem.eql;
    const tail = rest(ll.text, word);
    if (isAny(word, &include_words)) return include(r, tail, ll.line, word[0] != 'i');
    if (eql(u8, word, "define")) return define(r, tail, ll.line, false);
    if (eql(u8, word, "undefine")) return undefine(r, tail, ll.line, false);
    if (eql(u8, word, "endef")) return r.fail(ll.line, "extraneous 'endef'", .{});
    assert(eql(u8, word, "override"));
    if (parser.leadingDirective(tail, &.{"define"})) |w| return define(r, rest(tail, w), ll.line, true);
    if (parser.leadingDirective(tail, &.{"undefine"})) |w| return undefine(r, rest(tail, w), ll.line, true);
    try r.p.feed(.{ .kind = .normal, .text = tail, .line = ll.line });
    const items = r.p.statements.items;
    if (items.len == r.applied or items[items.len - 1] != .assignment) {
        return r.fail(ll.line, "'override' needs a variable assignment", .{});
    }
    items[items.len - 1].assignment.override = true;
    try applyNew(r);
}

/// `define NAME [=|:=|::=|?=|+=]` ... `endef`.
fn define(r: *Reader, head: []const u8, line: u32, override: bool) Error!void {
    assert(line > 0);
    const ops = [_]struct { []const u8, ast.VariableFlavor }{
        .{ "::=", .simple }, .{ ":=", .simple }, .{ "?=", .conditional }, .{ "+=", .append }, .{ "=", .recursive },
    };
    var name = std.mem.trim(u8, head, ws);
    var flavor: ast.VariableFlavor = .recursive;
    for (ops) |op| {
        if (std.mem.endsWith(u8, name, op[0])) {
            name = std.mem.trim(u8, name[0 .. name.len - op[0].len], ws);
            flavor = op[1];
            break;
        }
    }
    if (name.len == 0) return r.fail(line, "empty variable name", .{});
    const body = try defineBody(r, line);
    try r.b.apply(r.ev, .{ .assignment = .{ .name = name, .flavor = flavor, .value = body, .line = line, .override = override } });
    assert(name.len > 0);
}

/// Read the raw lines up to the matching `endef`. Nested `define` blocks count.
fn defineBody(r: *Reader, line: u32) Error![]const u8 {
    assert(line > 0);
    const lx = &r.sources.items[r.sources.items.len - 1].lx;
    var out: std.ArrayList(u8) = .empty;
    var depth: u32 = 0;
    var n: u32 = 0;
    while (n < ast.limits.input_lines_max) : (n += 1) {
        const phys = lx.nextPhysical() orelse return r.fail(line, "missing 'endef', unterminated 'define'", .{});
        const t = std.mem.trimStart(u8, phys, " \t");
        if (startsWord(t, "endef")) {
            if (depth == 0) return out.items;
            depth -= 1;
        } else if (startsWord(t, "define") or (startsWord(t, "override") and startsWord(rest(t, "override"), "define"))) {
            depth += 1;
        }
        if (n > 0) try out.append(r.arena, '\n');
        try out.appendSlice(r.arena, phys);
    }
    assert(n == ast.limits.input_lines_max);
    return r.fail(line, "missing 'endef', unterminated 'define'", .{});
}

/// `include FILES`. The files are read in order, each as a new source on the
/// stack. `-include` and `sinclude` skip a file that does not exist.
fn include(r: *Reader, text: []const u8, line: u32, optional: bool) Error!void {
    assert(line > 0);
    r.ev.line = line;
    const names = try includeNames(r, try r.ev.expand(text, null));
    var found: std.ArrayList([2][]const u8) = .empty;
    for (names) |name| {
        const limit: Io.Limit = .limited(ast.limits.input_file_bytes_max);
        const data = r.ev.dir.readFileAlloc(r.ev.io, name, r.arena, limit) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.FileNotFound => {
                if (!optional and r.missing == null) r.missing = .{ .name = name, .file = r.filename, .line = line };
                continue;
            },
            error.StreamTooLong => return r.fail(line, "{s}: larger than {d} bytes", .{ name, ast.limits.input_file_bytes_max }),
            else => return r.fail(line, "{s}: {s}", .{ name, @errorName(err) }),
        };
        try found.append(r.arena, .{ name, data });
    }
    var i = found.items.len;
    while (i > 0) {
        i -= 1;
        try pushSource(r, found.items[i][1], 0, found.items[i][0], false);
    }
    assert(found.items.len <= names.len);
}

/// Split the expanded names. A name with `*`, `?` or `[` is a glob, as in GNU
/// Make: it gives the matching files, or itself when nothing matches.
fn includeNames(r: *Reader, text: []const u8) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var words: usize = 0;
    var it = std.mem.tokenizeAny(u8, text, ws);
    while (it.next()) |name| : (words += 1) {
        assert(name.len > 0);
        if (std.mem.indexOfAny(u8, name, "*?[") == null) {
            try out.append(r.arena, name);
            continue;
        }
        const matches = fns.wildcard(r.arena, r.ev.io, r.ev.dir, name) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return r.fail(r.ev.line, "{s}: {s}", .{ name, @errorName(err) }),
        };
        if (matches.len == 0) try out.append(r.arena, name) else try out.appendSlice(r.arena, try fns.splitWords(r.arena, matches));
    }
    assert(out.items.len >= words);
    return out.items;
}

/// GNU Make reports a missing include file after it reads all input, and then
/// tries to make the file. zmake does not remake included files (ADR-0012).
fn missingInclude(r: *Reader, m: Missing) Error {
    assert(m.name.len > 0 and m.line > 0);
    r.filename = m.file;
    r.warn(m.line, "{s}: No such file or directory", .{m.name});
    const has_rule = for (r.b.rules.items) |rule| {
        if (!rule.is_pattern and isAny(m.name, rule.targets)) break true;
    } else false;
    if (has_rule) {
        r.diag.set("*** zmake does not remake included files; make '{s}' first.  Stop.", .{m.name});
    } else {
        r.diag.set("*** No rule to make target '{s}'.  Stop.", .{m.name});
    }
    assert(r.diag.len > 0);
    return error.Syntax;
}

/// `undefine NAMES`. Without `override`, a command-line variable stays.
fn undefine(r: *Reader, text: []const u8, line: u32, override: bool) Error!void {
    assert(line > 0);
    r.ev.line = line;
    const names = try fns.splitWords(r.arena, try r.ev.expand(text, null));
    if (names.len == 0) return r.fail(line, "empty variable name", .{});
    for (names) |name| r.ev.undefine(name, if (override) .override else .file);
    assert(names.len > 0);
}

fn conditional(r: *Reader, word: []const u8, ll: lexer.LogicalLine) Error!void {
    const tail = rest(ll.text, word);
    const base = r.sources.items[r.sources.items.len - 1].cond_base;
    assert(r.conds.items.len >= base);
    if (std.mem.eql(u8, word, "endif")) {
        if (tail.len > 0) r.warn(ll.line, "extraneous text after 'endif' directive", .{});
        if (r.conds.items.len == base) return r.fail(ll.line, "extraneous 'endif'", .{});
        r.conds.items.len -= 1;
        return;
    }
    if (std.mem.eql(u8, word, "else")) return elseLine(r, tail, ll.line, base);
    if (r.conds.items.len >= ast.limits.conditional_depth_max) {
        return r.fail(ll.line, "conditionals nest more than {d} levels", .{ast.limits.conditional_depth_max});
    }
    const state: CondState = if (!r.active()) .ignored else if (try condition(r, word, tail, ll.line)) .active else .pending;
    try r.conds.append(r.arena, .{ .state = state, .seen_else = false });
    assert(r.conds.items.len > base);
}

fn elseLine(r: *Reader, tail: []const u8, line: u32, base: usize) Error!void {
    assert(r.conds.items.len >= base);
    if (r.conds.items.len == base) return r.fail(line, "extraneous 'else'", .{});
    const top = &r.conds.items[r.conds.items.len - 1];
    if (top.seen_else) return r.fail(line, "only one 'else' per conditional", .{});
    const chained = if (tail.len > 0) parser.leadingDirective(tail, &if_words) else null;
    if (tail.len > 0 and chained == null) r.warn(line, "extraneous text after 'else' directive", .{});
    top.state = switch (top.state) {
        .active => .done,
        .done, .ignored => top.state,
        .pending => if (chained) |w| (if (try condition(r, w, rest(tail, w), line)) .active else .pending) else .active,
    };
    if (chained == null) top.seen_else = true;
    assert(r.conds.items.len > base);
}

/// Evaluate the test of `ifeq`, `ifneq`, `ifdef` or `ifndef`.
fn condition(r: *Reader, word: []const u8, text: []const u8, line: u32) Error!bool {
    assert(isAny(word, &if_words));
    r.ev.line = line;
    if (word[2] == 'd' or word[3] == 'd') {
        const name = std.mem.trim(u8, try r.ev.expand(text, null), ws);
        const defined = if (name.len == 0) false else if (r.ev.lookup(name)) |v| v.value.len > 0 else false;
        return defined == std.mem.eql(u8, word, "ifdef");
    }
    const args = try eqArgs(r, text, line, word);
    const a = try r.ev.expand(args[0], null);
    const b = try r.ev.expand(args[1], null);
    assert(word[2] == 'e' or word[3] == 'e');
    return std.mem.eql(u8, a, b) == std.mem.eql(u8, word, "ifeq");
}

/// Split `(a,b)`, `"a" "b"` or `'a' 'b'`. In the parenthesis form, GNU Make
/// drops the white space before the comma and after it.
fn eqArgs(r: *Reader, text: []const u8, line: u32, word: []const u8) Error![2][]const u8 {
    assert(word.len > 0);
    if (text.len > 0 and text[0] == '(') {
        const comma = topLevel(text, 1, ',') orelse return r.fail(line, "invalid syntax in conditional", .{});
        const close = topLevel(text, comma + 1, ')') orelse return r.fail(line, "invalid syntax in conditional", .{});
        if (std.mem.trim(u8, text[close + 1 ..], ws).len > 0) r.warn(line, "extraneous text after '{s}' directive", .{word});
        return .{ std.mem.trimEnd(u8, text[1..comma], ws), std.mem.trimStart(u8, text[comma + 1 .. close], ws) };
    }
    const first = quoted(text) orelse return r.fail(line, "invalid syntax in conditional", .{});
    const after = std.mem.trimStart(u8, text[first.end..], ws);
    const second = quoted(after) orelse return r.fail(line, "invalid syntax in conditional", .{});
    if (std.mem.trim(u8, after[second.end..], ws).len > 0) r.warn(line, "extraneous text after '{s}' directive", .{word});
    assert(first.end <= text.len);
    return .{ first.text, second.text };
}

const Quoted = struct { text: []const u8, end: usize };

/// A `"..."` or `'...'` word at the start of `s`.
fn quoted(s: []const u8) ?Quoted {
    if (s.len < 2 or (s[0] != '"' and s[0] != '\'')) return null;
    assert(s[0] == '"' or s[0] == '\'');
    const close = std.mem.indexOfScalarPos(u8, s, 1, s[0]) orelse return null;
    assert(close >= 1 and close < s.len);
    return .{ .text = s[1..close], .end = close + 1 };
}

/// The index of `target` at parenthesis depth 0, from `start`.
fn topLevel(s: []const u8, start: usize, target: u8) ?usize {
    assert(target == ',' or target == ')');
    var depth: usize = 0;
    var i = start;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (depth == 0 and c == target) return i;
        if (c == '(' or c == '{') depth += 1;
        if ((c == ')' or c == '}') and depth > 0) depth -= 1;
    }
    assert(i == s.len);
    return null;
}

/// The text after the directive word, without leading white space.
fn rest(text: []const u8, word: []const u8) []const u8 {
    assert(word.len <= text.len);
    const tail = std.mem.trimStart(u8, text[word.len..], ws);
    assert(tail.len <= text.len);
    return tail;
}

fn startsWord(t: []const u8, word: []const u8) bool {
    assert(word.len > 0);
    if (!std.mem.startsWith(u8, t, word)) return false;
    assert(t.len >= word.len);
    return t.len == word.len or std.mem.indexOfScalar(u8, " \t#", t[word.len]) != null;
}

fn isAny(word: []const u8, list: []const []const u8) bool {
    assert(list.len > 0);
    assert(word.len > 0);
    for (list) |w| {
        if (std.mem.eql(u8, w, word)) return true;
    }
    return false;
}

const testing = std.testing;

fn readTest(arena: std.mem.Allocator, src: []const u8, mode: ast.SyntaxMode, diag: *Diagnostic) !struct { db: database.Database, ev: *eval.Evaluator } {
    const ev = try arena.create(eval.Evaluator);
    ev.* = eval.Evaluator.init(arena, testing.io, std.Io.Dir.cwd(), diag);
    try ev.define("CLI", "cmdline", false, .command_line);
    const db = try read(ev, src, "Makefile", mode, diag);
    return .{ .db = db, .ev = ev };
}

fn testValue(ev: *eval.Evaluator, name: []const u8) ![]const u8 {
    return ev.expand(try std.fmt.allocPrint(ev.arena, "$({s})", .{name}), null);
}

test "conditionals see the variables above them" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const src =
        \\A = a
        \\E =
        \\R = $(E)
        \\ifeq (a ,a)
        \\T1 = yes
        \\endif
        \\ifeq ( a,a )
        \\T2 = yes
        \\else
        \\T2 = no
        \\endif
        \\ifneq "$(A)" 'b'
        \\T3 = yes
        \\endif
        \\ifdef R
        \\T4 = defined
        \\endif
        \\ifdef E
        \\T5 = defined
        \\else ifeq (1,1)
        \\T5 = chained
        \\else
        \\T5 = never
        \\endif
        \\ifeq (1,2)
        \\  ifeq (bad syntax here
        \\  $(error never)
        \\  endif
        \\endif
        \\
    ;
    const r = try readTest(arena.allocator(), src, .legacy, &diag);
    try testing.expectEqualStrings("yes", try testValue(r.ev, "T1"));
    try testing.expectEqualStrings("no", try testValue(r.ev, "T2"));
    try testing.expectEqualStrings("yes", try testValue(r.ev, "T3"));
    try testing.expectEqualStrings("defined", try testValue(r.ev, "T4"));
    try testing.expectEqualStrings("chained", try testValue(r.ev, "T5"));
}

test "a conditional inside a recipe selects recipe lines" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const src = "MODE = fast\nall:\nifeq ($(MODE),fast)\n\techo fast\nelse\n\techo slow\nendif\n\techo after\n";
    const r = try readTest(arena.allocator(), src, .legacy, &diag);
    try testing.expectEqual(@as(usize, 1), r.db.rules.len);
    const recipes = r.db.rules[0].recipes;
    try testing.expectEqual(@as(usize, 2), recipes.len);
    try testing.expectEqualStrings("echo fast", recipes[0].text);
    try testing.expectEqualStrings("echo after", recipes[1].text);
    const modern = try readTest(arena.allocator(), "build:\nifdef NOPE\n    echo a\nelse\n    echo b\nendif\n", .modern, &diag);
    try testing.expectEqualStrings("echo b", modern.db.rules[0].recipes[0].text);
}

test "define, override and undefine" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const src = "A = a\ndefine MULTI\nline one\n\ttab line # not a comment\nendef\n" ++
        "define SIMPLE :=\nv=$(A)\nendef\ndefine OUTER\ndefine INNER\nx\nendef\nendef\n" ++
        "override CLI = file\nU = 1\nundefine U\n";
    const r = try readTest(arena.allocator(), src, .legacy, &diag);
    try testing.expectEqualStrings("line one\n\ttab line # not a comment", try testValue(r.ev, "MULTI"));
    try testing.expectEqualStrings("v=a", r.ev.lookup("SIMPLE").?.value);
    try testing.expect(!r.ev.lookup("SIMPLE").?.recursive);
    try testing.expectEqualStrings("define INNER\nx\nendef", r.ev.lookup("OUTER").?.value);
    try testing.expectEqualStrings("file", r.ev.lookup("CLI").?.value);
    try testing.expectEqual(ast.Origin.override, r.ev.lookup("CLI").?.origin);
    try testing.expect(r.ev.lookup("U") == null);
}

test "eval texts define variables and rules" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const src = "$(foreach t,a b,$(eval $(t)_OBJ := $(t).o))\nX := $(a_OBJ) $(b_OBJ)\n" ++
        "define RULE\ngen-$(1): $(1).in\n\t@echo making $$@\nendef\n$(eval $(call RULE,x))\nall: gen-x\n";
    const r = try readTest(arena.allocator(), src, .legacy, &diag);
    try testing.expectEqualStrings("a.o b.o", r.ev.lookup("X").?.value);
    try testing.expectEqual(@as(usize, 2), r.db.rules.len);
    try testing.expectEqualStrings("gen-x", r.db.rules[0].targets[0]);
    try testing.expectEqualStrings("echo making $@", r.db.rules[0].recipes[0].text);
    try testing.expect(r.db.rules[0].recipes[0].silent);
    try testing.expectEqualStrings("gen-x", r.db.default_goal.?);
    r.ev.reading = false;
    try testing.expectError(error.Eval, r.ev.expand("$(eval Z := 1)", null));
}

test "reader errors" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    const cases = [_][2][]const u8{
        .{ "ifeq (a,a)\nX=1\n", "Makefile:3: *** missing 'endif'.  Stop." },
        .{ "endif\n", "Makefile:1: *** extraneous 'endif'.  Stop." },
        .{ "ifeq (a,a)\nelse\nelse\nendif\n", "Makefile:3: *** only one 'else' per conditional.  Stop." },
        .{ "ifeq a,a\nendif\n", "Makefile:1: *** invalid syntax in conditional.  Stop." },
        .{ "define X\nabc\n", "Makefile:1: *** missing 'endef', unterminated 'define'.  Stop." },
        .{ "endef\n", "Makefile:1: *** extraneous 'endef'.  Stop." },
    };
    for (cases) |c| {
        try testing.expectError(error.Syntax, readTest(a, c[0], .legacy, &diag));
        try testing.expectEqualStrings(c[1], diag.message());
    }
}

test "include reads files in order and names each file" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "mk");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "mk/a.mk", .data = "X += a\ninclude mk/b.mk\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "mk/b.mk", .data = "X += b\nlib:\n\techo lib\n" });
    var ev = eval.Evaluator.init(a, testing.io, tmp.dir, &diag);
    const db = try read(&ev, "X = main\ninclude mk/a.mk\n-include nope.mk\nall: lib\n", "Makefile", .legacy, &diag);
    try testing.expectEqualStrings("main a b", try ev.expand("$(X)", null));
    try testing.expectEqualStrings("Makefile mk/a.mk mk/b.mk", ev.lookup("MAKEFILE_LIST").?.value);
    try testing.expectEqualStrings("mk/b.mk", db.rules[0].file);
    try testing.expectEqual(@as(u32, 2), db.rules[0].source_line);
    try testing.expectEqualStrings("Makefile", db.rules[1].file);
    var ev2 = eval.Evaluator.init(a, testing.io, tmp.dir, &diag);
    try testing.expectError(error.Syntax, read(&ev2, "include nope.mk\nall:\n", "Makefile", .legacy, &diag));
    try testing.expectEqualStrings("*** No rule to make target 'nope.mk'.  Stop.", diag.message());
}
