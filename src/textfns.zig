//! Pure text and file name functions of GNU Make: `filter`, `sort`, `word`,
//! `dir`, `basename`, `join`, `abspath` and the others. They take expanded
//! arguments and return new text. None of them reads the disk, and none calls
//! itself (ADR-0003, rule R1). The evaluator validates numeric arguments.

const std = @import("std");
const assert = std.debug.assert;
const fns = @import("functions.zig");

const Allocator = std.mem.Allocator;
const OutOfMemory = error{OutOfMemory};
const ws = fns.whitespace;

/// `$(filter patterns,text)` or, with `keep == false`, `$(filter-out ...)`.
pub fn filter(arena: Allocator, patterns: []const u8, text: []const u8, keep: bool) OutOfMemory![]const u8 {
    const pats = try fns.splitWords(arena, patterns);
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, ws);
    while (it.next()) |word| {
        assert(word.len > 0);
        const hit = for (pats) |p| {
            if (fns.matchPattern(p, word) != null) break true;
        } else false;
        if (hit == keep) try fns.appendWord(arena, &out, word);
    }
    assert(out.items.len <= text.len);
    return out.items;
}

/// `$(findstring find,in)`: `find` when `in` contains it, else empty.
pub fn findstring(find: []const u8, in: []const u8) []const u8 {
    const found = std.mem.indexOf(u8, in, find) != null;
    assert(!found or find.len <= in.len);
    const result = if (found) find else "";
    assert(result.len <= find.len);
    return result;
}

/// `$(sort list)`: the words in lexical order, without duplicates.
pub fn sort(arena: Allocator, text: []const u8) OutOfMemory![]const u8 {
    const words = try fns.splitWords(arena, text);
    const copy = try arena.dupe([]const u8, words);
    std.mem.sort([]const u8, copy, {}, lessThan);
    var out: std.ArrayList(u8) = .empty;
    for (copy, 0..) |w, i| {
        if (i > 0 and std.mem.eql(u8, copy[i - 1], w)) continue;
        try fns.appendWord(arena, &out, w);
    }
    assert(copy.len == words.len);
    assert(out.items.len <= text.len);
    return out.items;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    assert(a.len > 0);
    assert(b.len > 0);
    return std.mem.order(u8, a, b) == .lt;
}

/// `$(strip text)`: the words with one space between them.
pub fn strip(arena: Allocator, text: []const u8) OutOfMemory![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, ws);
    while (it.next()) |w| try fns.appendWord(arena, &out, w);
    assert(out.items.len <= text.len);
    assert(out.items.len == 0 or out.items[0] != ' ');
    return out.items;
}

/// `$(words text)`: the number of words, as decimal text.
pub fn countWords(arena: Allocator, text: []const u8) OutOfMemory![]const u8 {
    var n: usize = 0;
    var it = std.mem.tokenizeAny(u8, text, ws);
    while (it.next()) |w| {
        assert(w.len > 0);
        n += 1;
    }
    assert(n <= text.len);
    return std.fmt.allocPrint(arena, "{d}", .{n});
}

/// `$(wordlist start,end,text)` with `start >= 1`: words `start` to `end`, 1-based.
/// `$(word n,text)` is `wordlist(n, n, text)`.
pub fn wordlist(arena: Allocator, start: usize, end: usize, text: []const u8) OutOfMemory![]const u8 {
    assert(start >= 1);
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, ws);
    var i: usize = 1;
    while (it.next()) |w| : (i += 1) {
        if (i > end) break;
        if (i >= start) try fns.appendWord(arena, &out, w);
    }
    assert(out.items.len <= text.len);
    return out.items;
}

/// `$(firstword text)` or, with `last`, `$(lastword text)`.
pub fn edgeWord(text: []const u8, last: bool) []const u8 {
    var it = std.mem.tokenizeAny(u8, text, ws);
    var result: []const u8 = "";
    while (it.next()) |w| {
        assert(w.len > 0);
        result = w;
        if (!last) break;
    }
    assert(result.len <= text.len);
    return result;
}

pub const NamePart = enum { dir, notdir, suffix, basename };

/// `$(dir ...)`, `$(notdir ...)`, `$(suffix ...)` and `$(basename ...)`.
/// GNU Make keeps an empty `notdir` result as an empty word, so its output
/// keeps the separating space. `suffix` drops a word without a suffix.
pub fn namePart(arena: Allocator, text: []const u8, part: NamePart) OutOfMemory![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, ws);
    var first = true;
    while (it.next()) |w| : (first = false) {
        assert(w.len > 0);
        const slash = std.mem.lastIndexOfScalar(u8, w, '/');
        const file_start = if (slash) |s| s + 1 else 0;
        const dot = std.mem.lastIndexOfScalar(u8, w[file_start..], '.');
        const piece: []const u8 = switch (part) {
            .dir => if (slash) |s| w[0 .. s + 1] else "./",
            .notdir => w[file_start..],
            .suffix => if (dot) |d| w[file_start + d ..] else continue,
            .basename => if (dot) |d| w[0 .. file_start + d] else w,
        };
        if (part == .notdir) {
            if (!first) try out.append(arena, ' ');
            try out.appendSlice(arena, piece);
        } else if (piece.len > 0) {
            try fns.appendWord(arena, &out, piece);
        }
    }
    assert(out.items.len <= text.len * 2 + 2);
    return out.items;
}

/// `$(addprefix p,names)` or, with `suffix`, `$(addsuffix s,names)`.
pub fn addAffix(arena: Allocator, affix: []const u8, text: []const u8, suffix: bool) OutOfMemory![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, ws);
    while (it.next()) |w| {
        assert(w.len > 0);
        if (out.items.len > 0) try out.append(arena, ' ');
        if (!suffix) try out.appendSlice(arena, affix);
        try out.appendSlice(arena, w);
        if (suffix) try out.appendSlice(arena, affix);
    }
    assert(out.items.len >= std.mem.trim(u8, text, ws).len);
    return out.items;
}

/// `$(join a,b)`: join the words of `a` and `b` pair by pair.
pub fn join(arena: Allocator, a: []const u8, b: []const u8) OutOfMemory![]const u8 {
    const left = try fns.splitWords(arena, a);
    const right = try fns.splitWords(arena, b);
    var out: std.ArrayList(u8) = .empty;
    const n = @max(left.len, right.len);
    for (0..n) |i| {
        if (i > 0) try out.append(arena, ' ');
        if (i < left.len) try out.appendSlice(arena, left[i]);
        if (i < right.len) try out.appendSlice(arena, right[i]);
    }
    assert(out.items.len <= a.len + b.len + n);
    assert(n == 0 or out.items.len > 0);
    return out.items;
}

/// `$(abspath names)`: each name as an absolute path without `.`, `..` or
/// repeated slashes. `cwd` is the absolute working directory. No symlinks resolve.
pub fn abspath(arena: Allocator, cwd: []const u8, text: []const u8) OutOfMemory![]const u8 {
    assert(cwd.len > 0 and cwd[0] == '/');
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, ws);
    while (it.next()) |w| {
        assert(w.len > 0);
        const full = if (w[0] == '/') w else try std.mem.concat(arena, u8, &.{ cwd, "/", w });
        try fns.appendWord(arena, &out, try normalize(arena, full));
    }
    assert(out.items.len == 0 or out.items[0] == '/');
    return out.items;
}

/// Collapse `.`, `..` and repeated slashes in an absolute path.
fn normalize(arena: Allocator, path: []const u8) OutOfMemory![]const u8 {
    assert(path.len > 0 and path[0] == '/');
    var parts: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, path, '/');
    while (it.next()) |comp| {
        if (std.mem.eql(u8, comp, ".")) continue;
        if (std.mem.eql(u8, comp, "..")) {
            if (parts.items.len > 0) parts.items.len -= 1;
            continue;
        }
        try parts.append(arena, comp);
    }
    if (parts.items.len == 0) return "/";
    var out: std.ArrayList(u8) = .empty;
    for (parts.items) |p| {
        try out.append(arena, '/');
        try out.appendSlice(arena, p);
    }
    assert(out.items.len <= path.len);
    return out.items;
}

/// Join `words` with one space and a `$$` escape for each `$`, so a later
/// expansion gives the words back unchanged.
pub fn escapeDollars(arena: Allocator, words: []const []const u8) OutOfMemory![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (words, 0..) |w, i| {
        if (i > 0) try out.append(arena, ',');
        for (w) |c| {
            if (c == '$') try out.append(arena, '$');
            try out.append(arena, c);
        }
    }
    assert(out.items.len >= words.len -| 1);
    assert(words.len > 0 or out.items.len == 0);
    return out.items;
}

const testing = std.testing;

test "filter, filter-out, findstring" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("a.c c.h", try filter(a, "%.c %.h", "a.c b.o c.h", true));
    try testing.expectEqualStrings("b.o", try filter(a, "%.c %.h", "a.c b.o c.h", false));
    try testing.expectEqualStrings("a", findstring("a", "cat"));
    try testing.expectEqualStrings("", findstring("x", "cat"));
}

test "sort, strip, words, wordlist, firstword, lastword" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("a b c", try sort(a, "c b  c a"));
    try testing.expectEqualStrings("a b", try strip(a, "  a \t b  "));
    try testing.expectEqualStrings("3", try countWords(a, " a b c "));
    try testing.expectEqualStrings("b c", try wordlist(a, 2, 3, "a b c d"));
    try testing.expectEqualStrings("", try wordlist(a, 3, 2, "a b c"));
    try testing.expectEqualStrings("b c", try wordlist(a, 2, 9, "a b c"));
    try testing.expectEqualStrings("a", edgeWord("a b", false));
    try testing.expectEqualStrings("b", edgeWord("a b", true));
}

test "file name parts" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("src/ ./ /", try namePart(a, "src/a.c b.c /x", .dir));
    try testing.expectEqualStrings("a.c b.c ", try namePart(a, "src/a.c b.c dir/", .notdir));
    try testing.expectEqualStrings(".c .gz", try namePart(a, "a.c b src.d/x a.tar.gz", .suffix));
    try testing.expectEqualStrings("a src.d/x b a.tar", try namePart(a, "a.c src.d/x b a.tar.gz", .basename));
}

test "addprefix, addsuffix, join, abspath, escape" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("a.c b.c", try addAffix(a, ".c", "a b", true));
    try testing.expectEqualStrings("x/a x/b", try addAffix(a, "x/", "a b", false));
    try testing.expectEqualStrings("a1 b2 c", try join(a, "a b c", "1 2"));
    try testing.expectEqualStrings("/w/b /w/c /x /", try abspath(a, "/w", "a/../b ./c /x/./y/.. .."));
    try testing.expectEqualStrings("a$$b,c", try escapeDollars(a, &.{ "a$b", "c" }));
}
