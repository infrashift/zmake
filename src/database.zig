//! The rule database. `load` replays the statements of the input file through
//! the evaluator (immediate phase) and collects the expanded rules, the special
//! targets and the default goal. `classify` applies the target kind rules of the
//! "Syntax modes and target kinds" spec.

const std = @import("std");
const assert = std.debug.assert;
const ast = @import("ast.zig");
const fns = @import("functions.zig");
const eval = @import("eval.zig");

pub const Error = eval.Error;
pub const StringSet = std.StringHashMapUnmanaged(void);

pub const Database = struct {
    mode: ast.SyntaxMode,
    filename: []const u8,
    rules: []const ast.Rule,
    phony: StringSet = .empty,
    precious: StringSet = .empty,
    silent: StringSet = .empty,
    silent_all: bool = false,
    not_parallel: bool = false,
    delete_on_error: bool = false,
    default_goal: ?[]const u8 = null,
};

/// Suffixes of the GNU Make default `.SUFFIXES` list. A rule such as `.c.o:`
/// with these suffixes is an old-style suffix rule, which zmake rejects.
const default_suffixes = [_][]const u8{
    ".out", ".a",   ".ln", ".o",   ".c",   ".cc",  ".C",   ".cpp", ".p",    ".f",   ".F",   ".m",       ".r",    ".y",      ".l",
    ".ym",  ".yl",  ".s",  ".S",   ".mod", ".sym", ".def", ".h",   ".info", ".dvi", ".tex", ".texinfo", ".texi", ".txinfo", ".w",
    ".ch",  ".web", ".sh", ".elc", ".el",
};

const Builder = struct {
    db: Database,
    rules: std.ArrayList(ast.Rule) = .empty,
    goal_from_target: ?[]const u8 = null,
};

pub fn load(ev: *eval.Evaluator, mk: ast.Makefile) Error!Database {
    assert(mk.filename.len > 0);
    ev.filename = mk.filename;
    var b: Builder = .{ .db = .{ .mode = mk.mode, .filename = mk.filename, .rules = &.{} } };
    for (mk.statements) |st| {
        switch (st) {
            .assignment => |a| {
                ev.line = a.line;
                try assign(ev, a);
            },
            .rule => |r| {
                ev.line = r.line;
                try addRule(ev, &b, r);
            },
        }
    }
    b.db.rules = b.rules.items;
    ev.line = 0;
    if (ev.lookup(".DEFAULT_GOAL")) |v| {
        const value = if (v.recursive) try ev.expand(v.value, null) else v.value;
        var it = std.mem.tokenizeAny(u8, value, fns.whitespace);
        if (it.next()) |goal| b.db.default_goal = goal;
    }
    assert(b.db.rules.len <= mk.statements.len * ast.limits.names_per_line_max);
    return b.db;
}

fn assign(ev: *eval.Evaluator, a: ast.Assignment) Error!void {
    assert(a.name.len > 0);
    const name = std.mem.trim(u8, try ev.expand(a.name, null), fns.whitespace);
    if (name.len == 0) return ev.fail("empty variable name", .{});
    switch (a.flavor) {
        .simple => try ev.define(name, try ev.expand(a.value, null), false, .file),
        .recursive => try ev.define(name, a.value, true, .file),
        .conditional => if (ev.lookup(name) == null) try ev.define(name, a.value, true, .file),
        .append => {
            const old = ev.lookup(name) orelse return ev.define(name, a.value, true, .file);
            const add = if (old.recursive) a.value else try ev.expand(a.value, null);
            const joined = if (old.value.len == 0)
                add
            else if (add.len == 0)
                old.value
            else
                try std.mem.concat(ev.arena, u8, &.{ old.value, " ", add });
            try ev.define(name, joined, old.recursive, .file);
        },
    }
    assert(ev.lookup(name) != null);
}

fn addRule(ev: *eval.Evaluator, b: *Builder, r: ast.RuleDecl) Error!void {
    assert(r.targets.len > 0);
    const targets = try fns.splitWords(ev.arena, try ev.expand(r.targets, null));
    if (targets.len == 0) return;
    const prereqs = try fns.splitWords(ev.arena, try ev.expand(r.prerequisites, null));
    const order_only = try fns.splitWords(ev.arena, try ev.expand(r.order_only, null));
    var specials: usize = 0;
    for (targets) |t| {
        if (ast.isSpecialTarget(t)) specials += 1;
    }
    if (specials > 0) {
        if (specials != targets.len) return ev.fail("mix of special and other targets in one rule", .{});
        for (targets) |t| try addSpecial(ev, b, t, prereqs);
        return;
    }
    if (targets.len == 1 and prereqs.len == 0 and isSuffixRule(targets[0])) {
        return ev.fail("suffix rule '{s}' is not supported; use a pattern rule", .{targets[0]});
    }
    const is_pattern = ast.isPattern(targets[0]);
    for (targets) |t| {
        if (ast.isPattern(t) != is_pattern) return ev.fail("mix of pattern and other targets in one rule", .{});
    }
    try b.rules.append(ev.arena, .{
        .targets = targets,
        .prerequisites = prereqs,
        .order_only = order_only,
        .recipes = r.recipes,
        .has_recipe = r.has_recipe,
        .task = r.task,
        .is_pattern = is_pattern,
        .source_line = r.line,
    });
    if (b.db.default_goal == null and !is_pattern) {
        const first = targets[0];
        if (first[0] != '.' or std.mem.indexOfScalar(u8, first, '/') != null) b.db.default_goal = first;
    }
    assert(b.rules.items.len > 0);
}

fn addSpecial(ev: *eval.Evaluator, b: *Builder, target: []const u8, prereqs: []const []const u8) Error!void {
    assert(ast.isSpecialTarget(target));
    const eql = std.mem.eql;
    if (eql(u8, target, ".PHONY")) {
        for (prereqs) |p| try b.db.phony.put(ev.arena, p, {});
    } else if (eql(u8, target, ".DEFAULT_GOAL")) {
        if (prereqs.len > 0) try ev.define(".DEFAULT_GOAL", prereqs[0], false, .file);
    } else if (eql(u8, target, ".PRECIOUS") or eql(u8, target, ".SECONDARY")) {
        for (prereqs) |p| try b.db.precious.put(ev.arena, p, {});
    } else if (eql(u8, target, ".SILENT")) {
        if (prereqs.len == 0) b.db.silent_all = true;
        for (prereqs) |p| try b.db.silent.put(ev.arena, p, {});
    } else if (eql(u8, target, ".NOTPARALLEL")) {
        b.db.not_parallel = true;
    } else if (eql(u8, target, ".DELETE_ON_ERROR")) {
        b.db.delete_on_error = true;
    } else if (isIgnoredSpecial(target)) {
        // These targets change nothing in zmake. See the CLI contract spec.
    } else {
        return ev.fail("special target '{s}' is not supported", .{target});
    }
    assert(target[0] == '.');
}

fn isIgnoredSpecial(target: []const u8) bool {
    const ignored = [_][]const u8{
        ".SUFFIXES", ".INTERMEDIATE", ".NOTINTERMEDIATE", ".POSIX", ".LOW_RESOLUTION_TIME",
    };
    for (ignored) |name| {
        if (std.mem.eql(u8, target, name)) return true;
    }
    assert(target.len > 0 and target[0] == '.');
    return false;
}

/// True for `.c` or `.c.o` when each part is a default suffix.
fn isSuffixRule(name: []const u8) bool {
    assert(name.len > 0);
    if (name[0] != '.' or std.mem.indexOfAny(u8, name, "/%") != null) return false;
    const second = std.mem.indexOfScalarPos(u8, name, 1, '.') orelse name.len;
    assert(second >= 1);
    if (!isDefaultSuffix(name[0..second])) return false;
    return second == name.len or isDefaultSuffix(name[second..]);
}

fn isDefaultSuffix(s: []const u8) bool {
    assert(s.len > 0 and s[0] == '.');
    for (default_suffixes) |suffix| {
        if (std.mem.eql(u8, s, suffix)) return true;
    }
    return false;
}

/// The facts about one target that the classifier needs.
pub const TargetFacts = struct {
    /// True when a rule for the target has a recipe or a prerequisite list.
    has_rule: bool,
    /// Modern mode: a rule declares the target with `@name:` or `task name:`.
    task: bool,
    /// True when a pattern rule makes the target.
    from_pattern: bool,
    /// The unexpanded recipe of the rule that makes the target.
    recipes: []const ast.RecipeLine,
};

/// Apply the classification rules of the "Syntax modes and target kinds" spec.
pub fn classify(db: *const Database, name: []const u8, facts: TargetFacts) ast.TargetKind {
    assert(name.len > 0);
    assert(!facts.task or db.mode == .modern);
    if (db.phony.contains(name)) return .explicit_phony;
    if (db.mode == .legacy) return .file;
    if (facts.task) return .explicit_phony; // Rule A
    if (!facts.has_rule or facts.from_pattern) return .file;
    if (std.mem.indexOfAny(u8, name, "/.") != null) return .file; // Rule B
    for (facts.recipes) |r| {
        if (refersToTarget(r.text)) return .file; // Rule B
    }
    return .inferred_phony; // Rule C
}

/// True when unexpanded recipe text refers to `$@`, `$(@)`, `${@}` or a D/F form.
pub fn refersToTarget(text: []const u8) bool {
    var i: usize = 0;
    while (i + 1 < text.len) : (i += 1) {
        if (text[i] != '$') continue;
        const rest = text[i + 1 ..];
        assert(rest.len >= 1);
        if (rest[0] == '$') {
            i += 1; // `$$` is a literal dollar sign.
            continue;
        }
        if (rest[0] == '@') return true;
        const forms = [_][]const u8{ "(@)", "(@D)", "(@F)", "{@}", "{@D}", "{@F}" };
        for (forms) |f| {
            if (std.mem.startsWith(u8, rest, f)) return true;
        }
    }
    assert(i + 1 >= text.len);
    return false;
}

const testing = std.testing;
const parser = @import("parser.zig");
const Diagnostic = @import("diag.zig").Diagnostic;

fn loadTest(arena: std.mem.Allocator, src: []const u8, mode: ast.SyntaxMode, diag: *Diagnostic) !Database {
    const mk = try parser.parse(arena, src, "Makefile", mode, diag);
    var ev = eval.Evaluator.init(arena, testing.io, std.Io.Dir.cwd(), diag);
    const db = try load(&ev, mk);
    return db;
}

test "load expands targets at definition time" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const src = "OBJS = a.o\nX := $(OBJS)\napp: $(OBJS)\nOBJS += b.o\nlib: $(OBJS) $(X)\n";
    const db = try loadTest(arena.allocator(), src, .legacy, &diag);
    try testing.expectEqual(@as(usize, 2), db.rules.len);
    try testing.expectEqual(@as(usize, 1), db.rules[0].prerequisites.len);
    try testing.expectEqual(@as(usize, 3), db.rules[1].prerequisites.len);
    try testing.expectEqualStrings("app", db.default_goal.?);
}

test "append keeps the flavor; conditional respects definitions" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    const mk = try parser.parse(a, "A := 1\nA += $(B)\nR = x\nR += $(B)\nB = 2\nC ?= 3\nC ?= 4\n", "Makefile", .legacy, &diag);
    var ev = eval.Evaluator.init(a, testing.io, std.Io.Dir.cwd(), &diag);
    _ = try load(&ev, mk);
    try testing.expectEqualStrings("1", ev.lookup("A").?.value);
    try testing.expectEqualStrings("x 2", try ev.expand("$(R)", null));
    try testing.expectEqualStrings("3", ev.lookup("C").?.value);
}

test "special targets and default goal" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const src = ".PHONY: all clean\n.SUFFIXES:\n%.o: %.c\n.hidden:\nall: app\nclean:\n.DEFAULT_GOAL := clean\n";
    const db = try loadTest(arena.allocator(), src, .legacy, &diag);
    try testing.expect(db.phony.contains("all") and db.phony.contains("clean"));
    try testing.expectEqualStrings("clean", db.default_goal.?);
    try testing.expect(db.rules[0].is_pattern);
}

test "first rule is the default goal; dot targets and patterns are skipped" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const db = try loadTest(arena.allocator(), "%.o: %.c\n.hidden:\nall: x\n", .legacy, &diag);
    try testing.expectEqualStrings("all", db.default_goal.?);
}

test "unsupported forms fail at load" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    try testing.expectError(error.Eval, loadTest(a, ".c.o:\n\tcc -c $<\n", .legacy, &diag));
    try testing.expectEqualStrings("Makefile:1: *** suffix rule '.c.o' is not supported; use a pattern rule.  Stop.", diag.message());
    try testing.expectError(error.Eval, loadTest(a, ".ONESHELL:\n", .legacy, &diag));
    try testing.expectError(error.Eval, loadTest(a, ".PHONY all:\n", .legacy, &diag));
}

test "classification truth table" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    const legacy = try loadTest(a, ".PHONY: clean\n", .legacy, &diag);
    const modern = try loadTest(a, ".PHONY: clean\n", .modern, &diag);
    const none: []const ast.RecipeLine = &.{};
    const with_target = [_]ast.RecipeLine{parser.recipeLine("cc -o $(@F) x", 1)};
    const plain = [_]ast.RecipeLine{parser.recipeLine("echo $$@ $(CC)", 1)};
    const f = struct {
        fn facts(has_rule: bool, task: bool, from_pattern: bool, recipes: []const ast.RecipeLine) TargetFacts {
            return .{ .has_rule = has_rule, .task = task, .from_pattern = from_pattern, .recipes = recipes };
        }
    }.facts;
    try testing.expectEqual(ast.TargetKind.explicit_phony, classify(&legacy, "clean", f(true, false, false, none)));
    try testing.expectEqual(ast.TargetKind.file, classify(&legacy, "build", f(true, false, false, &plain)));
    try testing.expectEqual(ast.TargetKind.explicit_phony, classify(&modern, "clean", f(true, false, false, none)));
    try testing.expectEqual(ast.TargetKind.explicit_phony, classify(&modern, "deploy", f(true, true, false, none)));
    try testing.expectEqual(ast.TargetKind.file, classify(&modern, "bin/app", f(true, false, false, &plain)));
    try testing.expectEqual(ast.TargetKind.file, classify(&modern, "main.o", f(true, false, false, &plain)));
    try testing.expectEqual(ast.TargetKind.file, classify(&modern, "app", f(true, false, false, &with_target)));
    try testing.expectEqual(ast.TargetKind.file, classify(&modern, "gen", f(true, false, true, &plain)));
    try testing.expectEqual(ast.TargetKind.file, classify(&modern, "README", f(false, false, false, none)));
    try testing.expectEqual(ast.TargetKind.inferred_phony, classify(&modern, "build", f(true, false, false, &plain)));
    try testing.expectEqual(ast.TargetKind.inferred_phony, classify(&modern, "all", f(true, false, false, none)));
}

test "refers to target" {
    try testing.expect(refersToTarget("cc -o $@ x"));
    try testing.expect(refersToTarget("mkdir -p ${@D}"));
    try testing.expect(!refersToTarget("echo $$@"));
    try testing.expect(!refersToTarget("echo $(CC) @"));
    try testing.expect(!refersToTarget("$"));
}
