//! Dual-mode parser. It turns logical lines into assignments and rules, in file
//! order. Target and prerequisite text stays unexpanded: the evaluator expands it.

const std = @import("std");
const assert = std.debug.assert;
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const Diagnostic = @import("diag.zig").Diagnostic;

pub const Error = error{ Syntax, OutOfMemory };

/// Directives that the parser rejects (ADR-0005). The reader handles the
/// conditionals, `define`, `override` and `undefine` before the parser sees a
/// line, so `parse` alone still rejects them. `load` stays out of scope: it
/// loads a shared object into make.
const unsupported_directives = [_][]const u8{
    "include", "-include", "sinclude", "ifeq",  "ifneq",  "ifdef",    "ifndef",
    "else",    "endif",    "define",   "endef", "export", "unexport", "override",
    "vpath",   "undefine", "private",  "load",  "-load",
};

pub fn parse(
    arena: std.mem.Allocator,
    source: []const u8,
    filename: []const u8,
    mode: ast.SyntaxMode,
    diag: *Diagnostic,
) Error!ast.Makefile {
    assert(filename.len > 0);
    if (source.len > ast.limits.input_file_bytes_max) {
        diag.set("{s}: *** input file is larger than {d} bytes.  Stop.", .{ filename, ast.limits.input_file_bytes_max });
        return error.Syntax;
    }
    var p: Parser = .{ .arena = arena, .filename = filename, .mode = mode, .diag = diag };
    var lx: lexer.Lexer = .init(arena, source, mode, filename);
    while (try lx.next(p.open_rule != null, diag)) |ll| {
        assert(ll.line > 0 and ll.line <= lx.line);
        try p.feed(ll);
    }
    try p.closeRule();
    assert(p.open_rule == null);
    return .{ .mode = mode, .filename = filename, .statements = p.statements.items };
}

pub const Parser = struct {
    arena: std.mem.Allocator,
    filename: []const u8,
    mode: ast.SyntaxMode,
    diag: *Diagnostic,
    statements: std.ArrayList(ast.Statement) = .empty,
    open_rule: ?ast.RuleDecl = null,
    recipes: std.ArrayList(ast.RecipeLine) = .empty,

    fn fail(p: *Parser, line: u32, comptime fmt: []const u8, args: anytype) Error {
        assert(line > 0);
        var buf: [Diagnostic.capacity]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch "error";
        p.diag.set("{s}:{d}: *** {s}.  Stop.", .{ p.filename, line, msg });
        assert(p.diag.len > 0);
        return error.Syntax;
    }

    /// Take one logical line. A normal line closes the open rule first.
    pub fn feed(p: *Parser, ll: lexer.LogicalLine) Error!void {
        assert(ll.line > 0);
        switch (ll.kind) {
            .recipe => try p.addRecipe(ll),
            .normal => {
                try p.closeRule();
                try p.parseLine(ll);
            },
        }
        assert(ll.kind == .recipe or p.open_rule == null or p.recipes.items.len <= 1);
    }

    fn addRecipe(p: *Parser, ll: lexer.LogicalLine) Error!void {
        assert(ll.kind == .recipe);
        assert(p.open_rule != null);
        if (p.recipes.items.len >= ast.limits.recipe_lines_max) {
            return p.fail(ll.line, "more than {d} recipe lines in one rule", .{ast.limits.recipe_lines_max});
        }
        try p.recipes.append(p.arena, recipeLine(ll.text, ll.line));
        p.open_rule.?.has_recipe = true;
    }

    pub fn closeRule(p: *Parser) Error!void {
        var rule = p.open_rule orelse return;
        assert(rule.targets.len > 0);
        rule.recipes = try p.recipes.toOwnedSlice(p.arena);
        assert(p.recipes.items.len == 0);
        try p.statements.append(p.arena, .{ .rule = rule });
        p.open_rule = null;
    }

    fn parseLine(p: *Parser, ll: lexer.LogicalLine) Error!void {
        assert(ll.kind == .normal and p.open_rule == null);
        const text = ll.text;
        assert(text.len > 0);
        if (directiveName(text)) |name| return p.fail(ll.line, "unsupported directive '{s}'", .{name});
        const sep = findSeparator(text) orelse {
            if (std.mem.indexOfScalar(u8, text, '$') == null) return p.fail(ll.line, "missing separator", .{});
            return p.statements.append(p.arena, .{ .expression = .{ .text = text, .line = ll.line } });
        };
        switch (sep.kind) {
            .assign => |flavor| try p.addAssignment(text[0..sep.start], text[sep.end..], flavor, ll.line),
            .rule => try p.openRule(text[0..sep.start], text[sep.end..], ll.line),
            .double_colon => return p.fail(ll.line, "double-colon rules are not supported", .{}),
            .shell_assign => return p.fail(ll.line, "'!=' assignments are not supported", .{}),
            .semicolon => return p.fail(ll.line, "missing separator", .{}),
        }
    }

    fn addAssignment(p: *Parser, lhs: []const u8, rhs: []const u8, flavor: ast.VariableFlavor, line: u32) Error!void {
        const name = std.mem.trim(u8, lhs, " \t");
        if (name.len == 0) return p.fail(line, "empty variable name", .{});
        if (std.mem.indexOfAny(u8, name, " \t") != null) {
            return p.fail(line, "invalid variable name '{s}'", .{name});
        }
        const value = std.mem.trimStart(u8, rhs, " \t");
        assert(name.len > 0 and std.mem.indexOfAny(u8, name, " \t") == null);
        assert(value.len <= rhs.len);
        try p.statements.append(p.arena, .{ .assignment = .{ .name = name, .flavor = flavor, .value = value, .line = line } });
    }

    fn openRule(p: *Parser, lhs: []const u8, rhs: []const u8, line: u32) Error!void {
        assert(p.open_rule == null and p.recipes.items.len == 0);
        const head = try p.ruleTargets(lhs, line);
        var prereq_text = rhs;
        var has_recipe = false;
        if (findTopLevel(rhs, ";")) |semi| {
            prereq_text = rhs[0..semi];
            has_recipe = true;
            const inline_recipe = std.mem.trimStart(u8, rhs[semi + 1 ..], " \t");
            if (inline_recipe.len > 0) try p.recipes.append(p.arena, recipeLine(inline_recipe, line));
        }
        if (findTopLevel(prereq_text, "=") != null) {
            return p.fail(line, "target-specific variables are not supported", .{});
        }
        var normal = prereq_text;
        var order_only: []const u8 = "";
        if (findTopLevel(prereq_text, "|")) |bar| {
            normal = prereq_text[0..bar];
            order_only = std.mem.trim(u8, prereq_text[bar + 1 ..], " \t");
        }
        p.open_rule = .{
            .targets = head.targets,
            .prerequisites = std.mem.trim(u8, normal, " \t"),
            .order_only = order_only,
            .recipes = &.{},
            .has_recipe = has_recipe,
            .task = head.task,
            .line = line,
        };
        assert(p.open_rule.?.targets.len > 0);
    }

    const RuleHead = struct { targets: []const u8, task: bool };

    /// Modern mode: `@name` and `task name` declare tasks. Legacy mode keeps the text.
    fn ruleTargets(p: *Parser, lhs: []const u8, line: u32) Error!RuleHead {
        const text = std.mem.trim(u8, lhs, " \t");
        if (text.len == 0) return p.fail(line, "missing target name", .{});
        assert(text.len <= lhs.len);
        if (p.mode == .legacy) return .{ .targets = text, .task = false };
        if (std.mem.startsWith(u8, text, "task ") or std.mem.startsWith(u8, text, "task\t")) {
            const rest = std.mem.trim(u8, text[4..], " \t");
            if (rest.len == 0) return p.fail(line, "missing task name after 'task'", .{});
            if (std.mem.indexOfScalar(u8, rest, '@') != null) return p.fail(line, "use 'task' or '@', not both", .{});
            assert(rest.len > 0 and p.mode == .modern);
            return .{ .targets = rest, .task = true };
        }
        return p.stripTaskMarkers(text, line);
    }

    /// Remove the `@` marker from each word. All words carry it, or none do.
    fn stripTaskMarkers(p: *Parser, text: []const u8, line: u32) Error!RuleHead {
        assert(text.len > 0 and p.mode == .modern);
        if (std.mem.indexOfScalar(u8, text, '@') == null) return .{ .targets = text, .task = false };
        var out: std.ArrayList(u8) = .empty;
        var marked: usize = 0;
        var words: usize = 0;
        var it = std.mem.tokenizeAny(u8, text, " \t");
        while (it.next()) |word| {
            words += 1;
            const name = if (word[0] == '@') word[1..] else word;
            if (word[0] == '@') marked += 1;
            if (name.len == 0) return p.fail(line, "missing task name after '@'", .{});
            if (out.items.len > 0) try out.append(p.arena, ' ');
            try out.appendSlice(p.arena, name);
        }
        if (marked != words) return p.fail(line, "mix of tasks and other targets in one rule", .{});
        assert(words > 0 and out.items.len > 0);
        return .{ .targets = out.items, .task = true };
    }
};

/// Split the `@`, `-` and `+` prefixes from a recipe command.
pub fn recipeLine(text: []const u8, line: u32) ast.RecipeLine {
    assert(line > 0);
    var r: ast.RecipeLine = .{ .text = text, .silent = false, .ignore_error = false, .always_run = false, .line = line };
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        switch (text[i]) {
            '@' => r.silent = true,
            '-' => r.ignore_error = true,
            '+' => r.always_run = true,
            ' ', '\t' => {},
            else => break,
        }
    }
    r.text = text[i..];
    assert(r.text.len <= text.len);
    return r;
}

/// Return the directive word when the line starts with an unsupported directive.
fn directiveName(text: []const u8) ?[]const u8 {
    assert(text.len > 0);
    const word = leadingDirective(text, &unsupported_directives);
    assert(word == null or word.?.len > 0);
    return word;
}

/// Return the first word of `text` when it is one of `words` and the line is a
/// directive. `include = x` and `export: y` are a variable and a target.
pub fn leadingDirective(text: []const u8, words: []const []const u8) ?[]const u8 {
    assert(words.len > 0);
    const word_end = std.mem.indexOfAny(u8, text, " \t(") orelse text.len;
    const word = text[0..word_end];
    for (words) |d| {
        if (!std.mem.eql(u8, word, d)) continue;
        // `include = x` and `export: y` define a variable and a target, not a directive.
        const rest = std.mem.trimStart(u8, text[word_end..], " \t");
        if (rest.len > 0 and (rest[0] == '=' or rest[0] == ':' or
            std.mem.startsWith(u8, rest, "+=") or std.mem.startsWith(u8, rest, "?="))) return null;
        assert(word.len > 0);
        return word;
    }
    return null;
}

const SeparatorKind = union(enum) {
    assign: ast.VariableFlavor,
    rule,
    double_colon,
    shell_assign,
    semicolon,
};

const Separator = struct { kind: SeparatorKind, start: usize, end: usize };

/// Find the first top-level `=`, `:` or `;` and classify it.
fn findSeparator(text: []const u8) ?Separator {
    const i = findTopLevel(text, "=:;") orelse return null;
    assert(i < text.len);
    const c = text[i];
    if (c == ';') return .{ .kind = .semicolon, .start = i, .end = i + 1 };
    if (c == '=') {
        if (i > 0 and text[i - 1] == '+') return .{ .kind = .{ .assign = .append }, .start = i - 1, .end = i + 1 };
        if (i > 0 and text[i - 1] == '?') return .{ .kind = .{ .assign = .conditional }, .start = i - 1, .end = i + 1 };
        if (i > 0 and text[i - 1] == '!') return .{ .kind = .shell_assign, .start = i - 1, .end = i + 1 };
        return .{ .kind = .{ .assign = .recursive }, .start = i, .end = i + 1 };
    }
    assert(c == ':');
    const rest = text[i..];
    if (std.mem.startsWith(u8, rest, "::=")) return .{ .kind = .{ .assign = .simple }, .start = i, .end = i + 3 };
    if (std.mem.startsWith(u8, rest, ":=")) return .{ .kind = .{ .assign = .simple }, .start = i, .end = i + 2 };
    if (std.mem.startsWith(u8, rest, "::")) return .{ .kind = .double_colon, .start = i, .end = i + 2 };
    return .{ .kind = .rule, .start = i, .end = i + 1 };
}

/// Return the index of the first byte from `set` outside `$(...)` and `${...}`.
/// A fixed stack holds the open references, so the scan needs no recursion.
pub fn findTopLevel(text: []const u8, set: []const u8) ?usize {
    assert(set.len > 0);
    var closers: [ast.limits.expansion_depth_max]u8 = undefined;
    var depth: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '$' and i + 1 < text.len) {
            const n = text[i + 1];
            if ((n == '(' or n == '{') and depth < closers.len) {
                closers[depth] = if (n == '(') ')' else '}';
                depth += 1;
            }
            i += 1; // Skip the byte after `$`, also for `$$` and `$@`.
        } else if (depth > 0 and c == closers[depth - 1]) {
            depth -= 1;
        } else if (depth == 0 and std.mem.indexOfScalar(u8, set, c) != null) {
            return i;
        }
    }
    assert(depth <= closers.len);
    return null;
}

const testing = std.testing;

fn parseTest(arena: std.mem.Allocator, src: []const u8, mode: ast.SyntaxMode) !ast.Makefile {
    var diag: Diagnostic = .{};
    return parse(arena, src, "Makefile", mode, &diag);
}

test "assignment flavors" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseTest(arena.allocator(), "A = 1\nB := $(A)\nC ::= 2\nD ?= 3\nE += 4\nF=x=y\n", .legacy);
    const want = [_]ast.VariableFlavor{ .recursive, .simple, .simple, .conditional, .append, .recursive };
    try testing.expectEqual(want.len, mk.statements.len);
    for (want, mk.statements) |flavor, st| try testing.expectEqual(flavor, st.assignment.flavor);
    try testing.expectEqualStrings("$(A)", mk.statements[1].assignment.value);
    try testing.expectEqualStrings("F", mk.statements[5].assignment.name);
    try testing.expectEqualStrings("x=y", mk.statements[5].assignment.value);
}

test "rule with order-only prerequisites and inline recipe" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseTest(arena.allocator(), "out/a.o: a.c $(HDRS) | out ; @$(CC) -c $<\n\t-rm -f x\n", .legacy);
    const r = mk.statements[0].rule;
    try testing.expectEqualStrings("out/a.o", r.targets);
    try testing.expectEqualStrings("a.c $(HDRS)", r.prerequisites);
    try testing.expectEqualStrings("out", r.order_only);
    try testing.expectEqual(@as(usize, 2), r.recipes.len);
    try testing.expect(r.recipes[0].silent);
    try testing.expectEqualStrings("$(CC) -c $<", r.recipes[0].text);
    try testing.expect(r.recipes[1].ignore_error);
    try testing.expectEqualStrings("rm -f x", r.recipes[1].text);
}

test "colon inside a variable reference is not a separator" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseTest(arena.allocator(), "$(SRC:.c=.o): x\n", .legacy);
    try testing.expectEqualStrings("$(SRC:.c=.o)", mk.statements[0].rule.targets);
}

test "errors carry file and line" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    try testing.expectError(error.Syntax, parse(a, "\nifeq ($(A),1)\n", "Makefile", .legacy, &diag));
    try testing.expectEqualStrings("Makefile:2: *** unsupported directive 'ifeq'.  Stop.", diag.message());
    try testing.expectError(error.Syntax, parse(a, "hello\n", "Makefile", .legacy, &diag));
    try testing.expectEqualStrings("Makefile:1: *** missing separator.  Stop.", diag.message());
    try testing.expectError(error.Syntax, parse(a, "a:: b\n", "Makefile", .legacy, &diag));
    try testing.expectError(error.Syntax, parse(a, "a: CC = x\n", "Makefile", .legacy, &diag));
    try testing.expectError(error.Syntax, parse(a, "X != ls\n", "Makefile", .legacy, &diag));
}

test "directive words used as names" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mk = try parseTest(arena.allocator(), "include = a\nexport: b\n", .legacy);
    try testing.expectEqualStrings("include", mk.statements[0].assignment.name);
    try testing.expectEqualStrings("export", mk.statements[1].rule.targets);
}

test "recipe prefixes" {
    const r = recipeLine("@-+ echo hi", 1);
    try testing.expect(r.silent and r.ignore_error and r.always_run);
    try testing.expectEqualStrings("echo hi", r.text);
}

test "find top level skips nested references and escapes" {
    try testing.expectEqual(@as(?usize, 13), findTopLevel("$(a $(b:c=d))=", "="));
    try testing.expectEqual(@as(?usize, null), findTopLevel("${x:y}", ":"));
    try testing.expectEqual(@as(?usize, 3), findTopLevel("$$a:", ":"));
}
