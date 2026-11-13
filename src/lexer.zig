//! Context-sensitive line lexer. It splits the input file into logical lines.
//! The parser tells the lexer whether a rule is open, because only then can a
//! line be a recipe line. See the "Syntax modes and target kinds" spec.

const std = @import("std");
const assert = std.debug.assert;
const ast = @import("ast.zig");
const Diagnostic = @import("diag.zig").Diagnostic;

pub const LineKind = enum { normal, recipe };

pub const LogicalLine = struct {
    kind: LineKind,
    /// Normal line: comments removed, continuations joined, leading space removed.
    /// Recipe line: the command with its tab or block indent removed.
    text: []const u8,
    /// The number of the first physical line, starting at 1.
    line: u32,
};

pub const Error = error{ Syntax, OutOfMemory };

pub const Lexer = struct {
    arena: std.mem.Allocator,
    source: []const u8,
    mode: ast.SyntaxMode,
    filename: []const u8,
    pos: usize = 0,
    line: u32 = 0,
    /// Modern mode: the space indent of the open recipe block.
    block_indent: ?usize = null,
    /// When not 0, every line reports this number. A `$(eval)` text reports
    /// the line of the statement that called `eval`.
    fixed_line: u32 = 0,

    pub fn init(arena: std.mem.Allocator, source: []const u8, mode: ast.SyntaxMode, filename: []const u8) Lexer {
        assert(source.len <= ast.limits.input_file_bytes_max);
        assert(filename.len > 0);
        return .{ .arena = arena, .source = source, .mode = mode, .filename = filename };
    }

    /// Return the next logical line, or null at the end of the input.
    /// `in_rule` is true when the parser has an open rule.
    pub fn next(lx: *Lexer, in_rule: bool, diag: *Diagnostic) Error!?LogicalLine {
        assert(lx.pos <= lx.source.len);
        if (!in_rule) lx.block_indent = null;
        assert(in_rule or lx.block_indent == null);
        var budget: u32 = ast.limits.input_lines_max;
        while (budget > 0) : (budget -= 1) {
            assert(lx.pos <= lx.source.len);
            const start_line = lx.line + 1;
            const phys = lx.readPhysical() orelse return null;
            if (in_rule) {
                if (try lx.recipePrefix(phys, start_line, diag)) |prefix_len| {
                    const text = try lx.joinRecipe(phys[prefix_len..]);
                    return .{ .kind = .recipe, .text = text, .line = lx.reported(start_line) };
                }
            }
            const trimmed = std.mem.trimStart(u8, phys, " \t");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            lx.block_indent = null;
            const text = try lx.joinNormal(phys);
            assert(lx.line >= start_line);
            if (std.mem.trim(u8, text, " \t").len == 0) continue;
            return .{ .kind = .normal, .text = text, .line = lx.reported(start_line) };
        }
        diag.set("{s}: *** more than {d} lines.  Stop.", .{ lx.filename, ast.limits.input_lines_max });
        return error.Syntax;
    }

    fn reported(lx: *const Lexer, line: u32) u32 {
        assert(line > 0);
        const n = if (lx.fixed_line > 0) lx.fixed_line else line;
        assert(n > 0);
        return n;
    }

    /// Return the next physical line as it is, for the body of `define`.
    pub fn nextPhysical(lx: *Lexer) ?[]const u8 {
        assert(lx.pos <= lx.source.len);
        lx.block_indent = null;
        const phys = lx.readPhysical();
        assert(phys == null or phys.?.len <= lx.source.len);
        return phys;
    }

    /// The number of the last line that the lexer read, for messages at the end.
    pub fn lastLine(lx: *const Lexer) u32 {
        assert(lx.pos <= lx.source.len);
        const n = lx.reported(lx.line + 1);
        assert(n > 0);
        return n;
    }

    /// Read one physical line without its newline. Drop a trailing carriage return.
    fn readPhysical(lx: *Lexer) ?[]const u8 {
        assert(lx.pos <= lx.source.len);
        if (lx.pos == lx.source.len) return null;
        const rest = lx.source[lx.pos..];
        const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
        lx.pos += @min(end + 1, rest.len);
        lx.line += 1;
        assert(lx.pos <= lx.source.len);
        return std.mem.trimEnd(u8, rest[0..end], "\r");
    }

    /// Return the length of the recipe prefix of `phys`, or null when `phys` is
    /// not a recipe line.
    fn recipePrefix(lx: *Lexer, phys: []const u8, line: u32, diag: *Diagnostic) Error!?usize {
        assert(phys.len <= lx.source.len);
        if (phys.len > 0 and phys[0] == '\t') return 1;
        if (lx.mode == .legacy) return null;
        const spaces = leadingSpaces(phys);
        if (spaces < 2 or spaces == phys.len) return null;
        const indent = lx.block_indent orelse blk: {
            lx.block_indent = spaces;
            break :blk spaces;
        };
        if (spaces < indent) {
            diag.set("{s}:{d}: *** recipe line has {d} spaces of indent; the block uses {d}.  Stop.", .{ lx.filename, line, spaces, indent });
            return error.Syntax;
        }
        assert(indent >= 2 and indent <= spaces);
        return indent;
    }

    /// Join recipe continuations. Keep each backslash-newline for the shell, and
    /// remove the recipe prefix of each continuation line, as GNU Make does.
    fn joinRecipe(lx: *Lexer, first: []const u8) Error![]const u8 {
        if (!endsWithContinuation(first)) return first;
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(lx.arena, first);
        var budget: u32 = ast.limits.input_lines_max;
        while (budget > 0 and endsWithContinuation(out.items)) : (budget -= 1) {
            assert(out.items.len > 0);
            const phys = lx.readPhysical() orelse break;
            try out.append(lx.arena, '\n');
            try out.appendSlice(lx.arena, lx.stripContinuationPrefix(phys));
        }
        assert(out.items.len >= first.len);
        return out.items;
    }

    fn stripContinuationPrefix(lx: *const Lexer, phys: []const u8) []const u8 {
        if (phys.len > 0 and phys[0] == '\t') return phys[1..];
        const indent = lx.block_indent orelse return phys;
        assert(lx.mode == .modern);
        const stripped = phys[@min(indent, leadingSpaces(phys))..];
        assert(stripped.len + indent >= phys.len);
        return stripped;
    }

    /// Join normal-line continuations. A backslash-newline and the white space
    /// around it become one space. Remove the comment. Keep trailing white space.
    fn joinNormal(lx: *Lexer, first: []const u8) Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        var current = std.mem.trimStart(u8, first, " \t");
        var budget: u32 = ast.limits.input_lines_max;
        while (budget > 0) : (budget -= 1) {
            assert(lx.pos <= lx.source.len);
            const cut = commentStart(current);
            if (cut == null and endsWithContinuation(current)) {
                const body = std.mem.trimEnd(u8, current[0 .. current.len - 1], " \t");
                try appendUnescaped(lx.arena, &out, body);
                const phys = lx.readPhysical() orelse break;
                current = std.mem.trimStart(u8, phys, " \t");
                if (out.items.len > 0 and current.len > 0) try out.append(lx.arena, ' ');
                continue;
            }
            try appendUnescaped(lx.arena, &out, current[0 .. cut orelse current.len]);
            break;
        }
        assert(budget > 0 or lx.pos == lx.source.len);
        return out.items;
    }
};

fn leadingSpaces(s: []const u8) usize {
    var n: usize = 0;
    while (n < s.len and s[n] == ' ') n += 1;
    assert(n <= s.len);
    assert(n == s.len or s[n] != ' ');
    return n;
}

/// True when `s` ends with an odd number of backslashes.
fn endsWithContinuation(s: []const u8) bool {
    var n: usize = 0;
    while (n < s.len and s[s.len - 1 - n] == '\\') n += 1;
    assert(n <= s.len);
    assert(n == s.len or s[s.len - 1 - n] != '\\');
    return n % 2 == 1;
}

/// Return the index of the first `#` that no backslash escapes.
fn commentStart(s: []const u8) ?usize {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\\' and i + 1 < s.len) {
            i += 1;
        } else if (s[i] == '#') {
            assert(i < s.len);
            return i;
        }
    }
    assert(i >= s.len);
    return null;
}

/// Append `s` and turn each `\#` into `#`. Keep every other backslash.
fn appendUnescaped(arena: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) Error!void {
    const before = out.items.len;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\\' and i + 1 < s.len and s[i + 1] == '#') {
            i += 1;
        }
        try out.append(arena, s[i]);
    }
    assert(out.items.len >= before);
    assert(out.items.len <= before + s.len);
}

const testing = std.testing;

fn testCollect(arena: std.mem.Allocator, src: []const u8, mode: ast.SyntaxMode, rule_after: []const u32) ![]const LogicalLine {
    var lx: Lexer = .init(arena, src, mode, "Makefile");
    var diag: Diagnostic = .{};
    var out: std.ArrayList(LogicalLine) = .empty;
    var in_rule = false;
    while (try lx.next(in_rule, &diag)) |ll| {
        try out.append(arena, ll);
        if (ll.kind == .normal) in_rule = std.mem.indexOfScalar(u32, rule_after, ll.line) != null;
    }
    return out.items;
}

test "legacy recipe lines need a tab" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const lines = try testCollect(arena.allocator(), "all: x\n\techo a\n    echo b\n", .legacy, &.{1});
    try testing.expectEqual(@as(usize, 3), lines.len);
    try testing.expectEqual(LineKind.recipe, lines[1].kind);
    try testing.expectEqualStrings("echo a", lines[1].text);
    try testing.expectEqual(LineKind.normal, lines[2].kind);
    try testing.expectEqualStrings("echo b", lines[2].text);
}

test "modern recipe lines accept spaces and keep the block indent" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const src = "build:\n    echo a\n\n    # note\n      echo b\nX = 1\n";
    const lines = try testCollect(arena.allocator(), src, .modern, &.{1});
    try testing.expectEqual(@as(usize, 5), lines.len);
    try testing.expectEqualStrings("echo a", lines[1].text);
    try testing.expectEqualStrings("# note", lines[2].text);
    try testing.expectEqualStrings("  echo b", lines[3].text);
    try testing.expectEqual(LineKind.normal, lines[4].kind);
}

test "modern recipe with less indent than the block is an error" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var lx: Lexer = .init(arena.allocator(), "a:\n    x\n  y\n", .modern, "ZMakefile");
    var diag: Diagnostic = .{};
    _ = try lx.next(false, &diag);
    _ = try lx.next(true, &diag);
    try testing.expectError(error.Syntax, lx.next(true, &diag));
    try testing.expectEqualStrings("ZMakefile:3: *** recipe line has 2 spaces of indent; the block uses 4.  Stop.", diag.message());
}

test "normal continuations collapse to one space and comments go away" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const lines = try testCollect(arena.allocator(), "SRC = a.c \\\n      b.c   \\\n  c.c # files\nH = \\#x\n", .legacy, &.{});
    try testing.expectEqual(@as(usize, 2), lines.len);
    try testing.expectEqualStrings("SRC = a.c b.c c.c ", lines[0].text);
    try testing.expectEqual(@as(u32, 1), lines[0].line);
    try testing.expectEqualStrings("H = #x", lines[1].text);
    try testing.expectEqual(@as(u32, 4), lines[1].line);
}

test "recipe continuations keep the backslash-newline" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const lines = try testCollect(arena.allocator(), "a:\n\techo 1 \\\n\t  2\n", .legacy, &.{1});
    try testing.expectEqual(@as(usize, 2), lines.len);
    try testing.expectEqualStrings("echo 1 \\\n  2", lines[1].text);
}

test "crlf line endings" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const lines = try testCollect(arena.allocator(), "a: b\r\n\techo\r\n", .legacy, &.{1});
    try testing.expectEqualStrings("a: b", lines[0].text);
    try testing.expectEqualStrings("echo", lines[1].text);
}
