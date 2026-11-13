//! Built-in Make functions and word helpers: `subst`, `patsubst`, `wildcard`,
//! `shell`, the D/F forms of automatic variables, and glob matching. No function
//! here calls itself (ADR-0003, rule R1).

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const ast = @import("ast.zig");

pub const Error = error{ OutOfMemory, LimitExceeded, ShellFailed, Io };

pub const whitespace = " \t\n\r";

/// Append `word` to `out` with one separating space.
pub fn appendWord(arena: std.mem.Allocator, out: *std.ArrayList(u8), word: []const u8) error{OutOfMemory}!void {
    assert(word.len > 0);
    const before = out.items.len;
    if (before > 0) try out.append(arena, ' ');
    try out.appendSlice(arena, word);
    assert(out.items.len > before);
}

/// Split `text` into words on white space.
pub fn splitWords(arena: std.mem.Allocator, text: []const u8) error{OutOfMemory}![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, whitespace);
    while (it.next()) |w| {
        assert(w.len > 0);
        try list.append(arena, w);
    }
    assert(list.items.len <= text.len);
    return list.items;
}

/// `$(subst from,to,text)`: replace each occurrence of `from` in `text`.
pub fn subst(arena: std.mem.Allocator, from: []const u8, to: []const u8, text: []const u8) error{OutOfMemory}![]const u8 {
    if (from.len == 0) return text;
    var out: std.ArrayList(u8) = .empty;
    var rest = text;
    while (std.mem.indexOf(u8, rest, from)) |i| {
        assert(i + from.len <= rest.len);
        try out.appendSlice(arena, rest[0..i]);
        try out.appendSlice(arena, to);
        rest = rest[i + from.len ..];
    }
    try out.appendSlice(arena, rest);
    assert(rest.len <= text.len);
    return out.items;
}

/// Match `word` against a pattern with at most one `%`. Return the stem, or null.
/// A pattern without `%` matches only the same word and gives an empty stem.
pub fn matchPattern(pattern: []const u8, word: []const u8) ?[]const u8 {
    assert(word.len > 0);
    const pct = std.mem.indexOfScalar(u8, pattern, '%') orelse {
        return if (std.mem.eql(u8, pattern, word)) word[0..0] else null;
    };
    const prefix = pattern[0..pct];
    const suffix = pattern[pct + 1 ..];
    if (word.len < prefix.len + suffix.len) return null;
    if (!std.mem.startsWith(u8, word, prefix) or !std.mem.endsWith(u8, word, suffix)) return null;
    const stem = word[prefix.len .. word.len - suffix.len];
    assert(prefix.len + stem.len + suffix.len == word.len);
    return stem;
}

/// Replace the first `%` in `replacement` with `stem`.
pub fn applyStem(arena: std.mem.Allocator, replacement: []const u8, stem: []const u8) error{OutOfMemory}![]const u8 {
    const pct = std.mem.indexOfScalar(u8, replacement, '%') orelse return replacement;
    assert(pct < replacement.len);
    const out = try std.mem.concat(arena, u8, &.{ replacement[0..pct], stem, replacement[pct + 1 ..] });
    assert(out.len == replacement.len - 1 + stem.len);
    return out;
}

/// `$(patsubst pattern,replacement,text)`.
pub fn patsubst(arena: std.mem.Allocator, pattern: []const u8, replacement: []const u8, text: []const u8) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, whitespace);
    const has_pct = std.mem.indexOfScalar(u8, pattern, '%') != null;
    while (it.next()) |word| {
        assert(word.len > 0);
        const replaced = if (matchPattern(pattern, word)) |stem|
            (if (has_pct) try applyStem(arena, replacement, stem) else replacement)
        else
            word;
        if (replaced.len > 0) try appendWord(arena, &out, replaced);
    }
    assert(out.items.len <= text.len * (replacement.len + 1) + text.len);
    return out.items;
}

/// `$(VAR:from=to)`: a suffix replacement, or a `patsubst` when `from` has `%`.
pub fn substRef(arena: std.mem.Allocator, from: []const u8, to: []const u8, text: []const u8) error{OutOfMemory}![]const u8 {
    if (std.mem.indexOfScalar(u8, from, '%') != null) return patsubst(arena, from, to, text);
    const pattern = try std.mem.concat(arena, u8, &.{ "%", from });
    const replacement = try std.mem.concat(arena, u8, &.{ "%", to });
    assert(pattern.len == from.len + 1);
    assert(replacement.len == to.len + 1);
    return patsubst(arena, pattern, replacement, text);
}

/// The `D` or `F` form of an automatic variable: the directory or file part of each word.
pub fn dirOrFile(arena: std.mem.Allocator, text: []const u8, part: u8) error{OutOfMemory}![]const u8 {
    assert(part == 'D' or part == 'F');
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, whitespace);
    while (it.next()) |word| {
        assert(word.len > 0);
        const slash = std.mem.lastIndexOfScalar(u8, word, '/');
        const piece = if (part == 'D')
            (if (slash) |s| (if (s == 0) "/" else word[0..s]) else ".")
        else
            (if (slash) |s| word[s + 1 ..] else word);
        if (piece.len > 0) try appendWord(arena, &out, piece);
    }
    return out.items;
}

/// Match `name` against a glob with `*`, `?` and `[...]`. The matcher keeps one
/// backtrack point for the last `*`, so it needs no recursion.
pub fn globMatch(pattern: []const u8, name: []const u8) bool {
    var p: usize = 0;
    var n: usize = 0;
    var star_p: ?usize = null;
    var star_n: usize = 0;
    var budget: usize = (pattern.len + 2) * (name.len + 2);
    while (budget > 0) : (budget -= 1) {
        assert(p <= pattern.len);
        assert(n <= name.len);
        if (p < pattern.len and pattern[p] == '*') {
            star_p = p;
            star_n = n;
            p += 1;
            continue;
        }
        if (n == name.len) {
            return p == pattern.len;
        }
        if (p < pattern.len) {
            if (matchOne(pattern, &p, name[n])) {
                n += 1;
                continue;
            }
        }
        const sp = star_p orelse return false;
        star_n += 1;
        n = star_n;
        p = sp + 1;
    }
    unreachable; // The budget covers every (p, n) pair.
}

/// Match one byte at `pattern[p.*]`. On a match, move `p` past the pattern element.
fn matchOne(pattern: []const u8, p: *usize, c: u8) bool {
    assert(p.* < pattern.len);
    const start = p.*;
    switch (pattern[start]) {
        '?' => {
            p.* += 1;
            return true;
        },
        '[' => {
            const close = std.mem.indexOfScalarPos(u8, pattern, start + 1, ']') orelse return literal(pattern, p, c);
            const set = pattern[start + 1 .. close];
            if (set.len == 0) return literal(pattern, p, c);
            const negate = set[0] == '!' or set[0] == '^';
            const body = if (negate) set[1..] else set;
            if (inSet(body, c) == negate) return false;
            p.* = close + 1;
            assert(p.* > start);
            return true;
        },
        '\\' => {
            if (start + 1 < pattern.len) p.* += 1;
            return literal(pattern, p, c);
        },
        else => return literal(pattern, p, c),
    }
}

fn literal(pattern: []const u8, p: *usize, c: u8) bool {
    assert(p.* < pattern.len);
    if (pattern[p.*] != c) return false;
    p.* += 1;
    assert(p.* <= pattern.len);
    return true;
}

fn inSet(body: []const u8, c: u8) bool {
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        if (i + 2 < body.len and body[i + 1] == '-') {
            if (c >= body[i] and c <= body[i + 2]) return true;
            i += 2;
        } else if (body[i] == c) {
            return true;
        }
    }
    assert(i >= body.len);
    return false;
}

/// `$(wildcard patterns)`: the existing paths that match each pattern, sorted
/// per pattern, as GNU Make 4.3 and later sort them.
pub fn wildcard(arena: std.mem.Allocator, io: Io, dir: Io.Dir, patterns: []const u8) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, patterns, whitespace);
    while (it.next()) |pattern| {
        assert(pattern.len > 0);
        const matches = try globPaths(arena, io, dir, pattern);
        std.mem.sort([]const u8, matches, {}, lessThan);
        assert(std.sort.isSorted([]const u8, matches, {}, lessThan));
        for (matches) |m| try appendWord(arena, &out, m);
    }
    return out.items;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    assert(a.len > 0 and b.len > 0);
    return std.mem.order(u8, a, b) == .lt;
}

/// Expand one glob pattern component by component, breadth first.
fn globPaths(arena: std.mem.Allocator, io: Io, dir: Io.Dir, pattern: []const u8) Error![][]const u8 {
    assert(pattern.len > 0);
    var current: std.ArrayList([]const u8) = .empty;
    try current.append(arena, if (pattern[0] == '/') "/" else "");
    var comps = std.mem.tokenizeScalar(u8, pattern, '/');
    while (comps.next()) |comp| {
        assert(comp.len > 0);
        var next: std.ArrayList([]const u8) = .empty;
        for (current.items) |base| {
            if (std.mem.indexOfAny(u8, comp, "*?[") != null) {
                try listMatches(arena, io, dir, base, comp, &next);
            } else {
                try next.append(arena, try joinPath(arena, base, comp));
            }
        }
        if (next.items.len > ast.limits.graph_nodes_max) return error.LimitExceeded;
        current = next;
    }
    var found: std.ArrayList([]const u8) = .empty;
    for (current.items) |path| {
        if (path.len == 0) continue;
        if (dir.access(io, path, .{})) |_| try found.append(arena, path) else |err| switch (err) {
            error.FileNotFound => {},
            else => return error.Io,
        }
    }
    assert(found.items.len <= current.items.len);
    return found.items;
}

fn joinPath(arena: std.mem.Allocator, base: []const u8, comp: []const u8) error{OutOfMemory}![]const u8 {
    assert(comp.len > 0);
    if (base.len == 0) return comp;
    const sep: []const u8 = if (base[base.len - 1] == '/') "" else "/";
    const joined = try std.mem.concat(arena, u8, &.{ base, sep, comp });
    assert(joined.len > comp.len);
    return joined;
}

/// Add each entry of directory `base` that matches `comp`. Skip dot files
/// unless the component starts with a dot.
fn listMatches(arena: std.mem.Allocator, io: Io, dir: Io.Dir, base: []const u8, comp: []const u8, out: *std.ArrayList([]const u8)) Error!void {
    assert(comp.len > 0);
    var sub = dir.openDir(io, if (base.len == 0) "." else base, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir, error.AccessDenied => return,
        else => return error.Io,
    };
    defer sub.close(io);
    var iter = sub.iterate();
    var budget: u32 = ast.limits.graph_nodes_max;
    while (budget > 0) : (budget -= 1) {
        const entry = (iter.next(io) catch return error.Io) orelse return;
        assert(entry.name.len > 0);
        if (entry.name[0] == '.' and comp[0] != '.') continue;
        if (!globMatch(comp, entry.name)) continue;
        try out.append(arena, try joinPath(arena, base, try arena.dupe(u8, entry.name)));
    }
    return error.LimitExceeded;
}

/// `$(shell command)`: run the command with `/bin/sh -c`. Turn each newline of
/// the output into a space. Drop the trailing newlines. The child's stderr goes
/// to the stderr of zmake.
pub fn shell(arena: std.mem.Allocator, io: Io, shell_path: []const u8, command: []const u8) Error![]const u8 {
    assert(shell_path.len > 0);
    const result = std.process.run(arena, io, .{
        .argv = &.{ shell_path, "-c", command },
        .stdout_limit = .limited(ast.limits.expansion_bytes_max),
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.StreamTooLong => return error.LimitExceeded,
        else => return error.ShellFailed,
    };
    if (result.stderr.len > 0) Io.File.stderr().writeStreamingAll(io, result.stderr) catch return error.Io;
    const trimmed = std.mem.trimEnd(u8, result.stdout, "\n");
    const out = try arena.dupe(u8, trimmed);
    for (out) |*c| {
        if (c.* == '\n') c.* = ' ';
    }
    assert(out.len == trimmed.len);
    return out;
}

const testing = std.testing;

test "subst" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("fEEt on the strEEt", try subst(arena.allocator(), "ee", "EE", "feet on the street"));
    try testing.expectEqualStrings("abc", try subst(arena.allocator(), "", "x", "abc"));
}

test "patsubst and substitution references" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("x.c.o bar.o", try patsubst(a, "%.c", "%.o", "x.c.c bar.c"));
    try testing.expectEqualStrings("out/a.o out/b.o z.h", try patsubst(a, "src/%.c", "out/%.o", "src/a.c  src/b.c z.h"));
    try testing.expectEqualStrings("a.o b.o", try substRef(a, ".c", ".o", "a.c b.c"));
    try testing.expectEqualStrings("lib", try patsubst(a, "x", "lib", "x"));
}

test "match pattern stems" {
    try testing.expectEqualStrings("main", matchPattern("%.o", "main.o").?);
    try testing.expectEqualStrings("a/b", matchPattern("src/%.c", "src/a/b.c").?);
    try testing.expect(matchPattern("%.o", "main.c") == null);
    try testing.expect(matchPattern("a%a", "a") == null);
}

test "dir and file parts" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("out . /", try dirOrFile(arena.allocator(), "out/a.o b.o /c", 'D'));
    try testing.expectEqualStrings("a.o b.o c", try dirOrFile(arena.allocator(), "out/a.o b.o /c", 'F'));
}

test "glob matching" {
    try testing.expect(globMatch("*.c", "main.c"));
    try testing.expect(!globMatch("*.c", "main.h"));
    try testing.expect(globMatch("a*b*c", "aXXbYYc"));
    try testing.expect(!globMatch("a*b*c", "aXXbYY"));
    try testing.expect(globMatch("?.[ch]", "x.h"));
    try testing.expect(!globMatch("?.[!ch]", "x.h"));
    try testing.expect(globMatch("[a-c]*", "beta"));
    try testing.expect(globMatch("*", ""));
    try testing.expect(globMatch("\\*", "*"));
}

test "wildcard lists sorted matches in subdirectories" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const io = testing.io;
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "src/sub");
    for ([_][]const u8{ "src/b.c", "src/a.c", "src/x.h", "src/.hidden.c", "src/sub/c.c" }) |f| {
        try tmp.dir.writeFile(io, .{ .sub_path = f, .data = "" });
    }
    const a = arena.allocator();
    try testing.expectEqualStrings("src/a.c src/b.c", try wildcard(a, io, tmp.dir, "src/*.c"));
    try testing.expectEqualStrings("src/sub/c.c", try wildcard(a, io, tmp.dir, "src/*/*.c"));
    try testing.expectEqualStrings("src/x.h", try wildcard(a, io, tmp.dir, "src/x.h nope.h"));
    try testing.expectEqualStrings("", try wildcard(a, io, tmp.dir, "*.zig"));
}

test "shell output joins lines" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("a b c", try shell(arena.allocator(), testing.io, "/bin/sh", "printf 'a\\nb\\nc\\n\\n'"));
}
