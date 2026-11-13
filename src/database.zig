//! The rule database. `load` replays the statements of the input file through
//! the evaluator (immediate phase) and collects the expanded rules, the special
//! targets and the default goal. `classify` applies the target kind rules of the
//! "Syntax modes and target kinds" spec.

const std = @import("std");
const assert = std.debug.assert;
const ast = @import("ast.zig");
const fns = @import("functions.zig");
const eval = @import("eval.zig");
const builtin_rules = @import("builtin_rules.zig");

pub const Error = eval.Error;
pub const StringSet = std.StringHashMapUnmanaged(void);

/// One target-specific or pattern-specific assignment, in file order.
pub const TargetAssign = struct {
    assignment: ast.Assignment,
    exported: bool,
    private: bool,
};

pub const PatternAssign = struct { pattern: []const u8, assign: TargetAssign };

/// `vpath PATTERN DIRS`: search DIRS for a missing file that matches PATTERN.
pub const Vpath = struct { pattern: []const u8, dirs: []const []const u8 };

pub const Database = struct {
    mode: ast.SyntaxMode,
    filename: []const u8,
    rules: []const ast.Rule,
    /// The `vpath` directives in file order.
    vpaths: []const Vpath = &.{},
    /// The directories of the `VPATH` variable, searched after `vpaths`.
    vpath_dirs: []const []const u8 = &.{},
    /// Target-specific assignments per target name, in file order.
    target_vars: std.StringHashMapUnmanaged(std.ArrayList(TargetAssign)) = .empty,
    /// Pattern-specific assignments, in file order.
    pattern_vars: []const PatternAssign = &.{},
    phony: StringSet = .empty,
    precious: StringSet = .empty,
    silent: StringSet = .empty,
    silent_all: bool = false,
    not_parallel: bool = false,
    delete_on_error: bool = false,
    default_goal: ?[]const u8 = null,
    /// The final `.SUFFIXES` list.
    suffixes: []const []const u8 = &.{},
};

/// The special targets of GNU Make. Another name that starts with a dot and
/// has no prerequisites can be an old-style suffix rule, such as `.c.o:`.
const special_targets = [_][]const u8{
    ".PHONY",               ".SUFFIXES",     ".DEFAULT",              ".PRECIOUS",        ".INTERMEDIATE",
    ".NOTINTERMEDIATE",     ".SECONDARY",    ".SECONDEXPANSION",      ".DELETE_ON_ERROR", ".IGNORE",
    ".LOW_RESOLUTION_TIME", ".SILENT",       ".EXPORT_ALL_VARIABLES", ".NOTPARALLEL",     ".ONESHELL",
    ".POSIX",               ".DEFAULT_GOAL", ".WAIT",
};

/// Collects the rules and the special targets while the statements arrive.
/// The reader applies each statement at once; `load` replays a parsed file.
pub const Builder = struct {
    db: Database,
    rules: std.ArrayList(ast.Rule) = .empty,
    vpaths: std.ArrayList(Vpath) = .empty,
    pattern_vars: std.ArrayList(PatternAssign) = .empty,
    /// The suffix list, filled with the GNU Make default on first use.
    suffixes: std.ArrayList([]const u8) = .empty,
    suffixes_ready: bool = false,
    /// Rules such as `.c.o:` and `.c:`. `finish` turns each one into a pattern
    /// rule when the final suffix list has its suffixes.
    suffix_candidates: std.ArrayList(ast.Rule) = .empty,

    pub fn init(mode: ast.SyntaxMode, filename: []const u8) Builder {
        assert(filename.len > 0);
        const b: Builder = .{ .db = .{ .mode = mode, .filename = filename, .rules = &.{} } };
        assert(b.rules.items.len == 0);
        return b;
    }

    /// Apply one statement. An expression must expand to nothing here; the
    /// reader reads a non-empty expansion again as input text instead.
    pub fn apply(b: *Builder, ev: *eval.Evaluator, st: ast.Statement) Error!void {
        assert(b.db.filename.len > 0);
        const before = b.rules.items.len;
        switch (st) {
            .assignment => |a| {
                ev.line = a.line;
                try assign(ev, a);
            },
            .rule => |r| {
                ev.line = r.line;
                try addRule(ev, b, r);
            },
            .expression => |e| {
                ev.line = e.line;
                const value = try ev.expand(e.text, null);
                if (std.mem.trim(u8, value, fns.whitespace).len > 0) return ev.fail("missing separator", .{});
            },
            .target_var => |tv| {
                ev.line = tv.assignment.line;
                try b.targetVariable(ev, tv);
            },
        }
        assert(b.rules.items.len >= before);
    }

    /// Store a target-specific assignment for each target. The name expands
    /// now; the value expands when the executor builds the target context.
    fn targetVariable(b: *Builder, ev: *eval.Evaluator, tv: ast.TargetVar) Error!void {
        assert(tv.targets.len > 0);
        const targets = try fns.splitWords(ev.arena, try ev.expand(tv.targets, null));
        var a = tv.assignment;
        a.name = std.mem.trim(u8, try ev.expand(a.name, null), fns.whitespace);
        if (a.name.len == 0) return ev.fail("empty variable name", .{});
        const entry: TargetAssign = .{ .assignment = a, .exported = tv.exported, .private = tv.private };
        for (targets) |t| {
            if (ast.isPattern(t)) {
                try b.pattern_vars.append(ev.arena, .{ .pattern = t, .assign = entry });
                continue;
            }
            const gop = try b.db.target_vars.getOrPut(ev.arena, t);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            try gop.value_ptr.append(ev.arena, entry);
        }
        assert(a.name.len > 0);
    }

    /// `vpath PATTERN DIRS` adds a search entry. `vpath PATTERN` (no dirs)
    /// removes the entries of PATTERN. `vpath` alone removes all entries.
    pub fn vpath(b: *Builder, ev: *eval.Evaluator, pattern: ?[]const u8, dirs: []const []const u8) Error!void {
        const p = pattern orelse {
            b.vpaths.clearRetainingCapacity();
            return;
        };
        assert(p.len > 0);
        if (dirs.len > 0) return b.vpaths.append(ev.arena, .{ .pattern = p, .dirs = dirs });
        var kept: usize = 0;
        for (b.vpaths.items) |v| {
            if (std.mem.eql(u8, v.pattern, p)) continue;
            b.vpaths.items[kept] = v;
            kept += 1;
        }
        b.vpaths.items.len = kept;
        assert(kept <= b.vpaths.capacity);
    }

    fn ensureSuffixes(b: *Builder, ev: *eval.Evaluator) Error!void {
        if (b.suffixes_ready) return;
        try b.suffixes.appendSlice(ev.arena, &builtin_rules.suffixes);
        b.suffixes_ready = true;
        assert(b.suffixes.items.len == builtin_rules.suffixes.len);
    }

    /// `.SUFFIXES:` with no names clears the list. With names, it adds them.
    fn setSuffixes(b: *Builder, ev: *eval.Evaluator, names: []const []const u8) Error!void {
        try b.ensureSuffixes(ev);
        if (names.len == 0) b.suffixes.clearRetainingCapacity();
        for (names) |n| {
            if (!inList(b.suffixes.items, n)) try b.suffixes.append(ev.arena, n);
        }
        assert(b.suffixes_ready);
    }

    /// Turn each suffix rule into a pattern rule: `.c.o:` into `%.o: %.c` and
    /// `.c:` into `%: %.c`. A name that the suffix list cannot split stays a
    /// file target, except an unknown special target, which is an error.
    fn convertSuffixRules(b: *Builder, ev: *eval.Evaluator) Error!void {
        assert(b.suffixes_ready);
        for (b.suffix_candidates.items) |cand| {
            const name = cand.targets[0];
            const pair = splitSuffixRule(b.suffixes.items, name) orelse {
                if (ast.isSpecialTarget(name)) {
                    ev.line = cand.source_line;
                    return ev.fail("special target '{s}' is not supported", .{name});
                }
                try b.rules.append(ev.arena, cand);
                continue;
            };
            var rule = cand;
            rule.targets = try ev.arena.dupe([]const u8, &.{try std.mem.concat(ev.arena, u8, &.{ "%", pair[1] })});
            rule.prerequisites = try ev.arena.dupe([]const u8, &.{try std.mem.concat(ev.arena, u8, &.{ "%", pair[0] })});
            rule.is_pattern = true;
            try b.rules.append(ev.arena, rule);
        }
        assert(b.rules.items.len >= b.suffix_candidates.items.len);
    }

    /// Add the built-in rules after the rules of the input file. A rule needs
    /// both of its suffixes in the list. A pattern rule of the input file with
    /// the same target and prerequisite replaces or cancels the built-in rule.
    fn addBuiltinRules(b: *Builder, ev: *eval.Evaluator) Error!void {
        const user_rules = b.rules.items.len;
        for (builtin_rules.rules) |br| {
            if (!inList(b.suffixes.items, br.source[1..])) continue;
            if (br.target.len > 1 and !inList(b.suffixes.items, br.target[1..])) continue;
            if (hasPatternRule(b.rules.items[0..user_rules], br.target, br.source)) continue;
            const recipe = try ev.arena.dupe(ast.RecipeLine, &.{.{ .text = br.recipe, .silent = false, .ignore_error = false, .always_run = false, .line = 0 }});
            try b.rules.append(ev.arena, .{
                .targets = try ev.arena.dupe([]const u8, &.{br.target}),
                .prerequisites = try ev.arena.dupe([]const u8, &.{br.source}),
                .order_only = &.{},
                .recipes = recipe,
                .has_recipe = true,
                .task = false,
                .is_pattern = true,
                .source_line = 0,
                .file = "<builtin>",
            });
        }
        assert(b.rules.items.len >= user_rules);
    }

    /// Take the rules and resolve `.DEFAULT_GOAL` and `VPATH`.
    pub fn finish(b: *Builder, ev: *eval.Evaluator) Error!Database {
        try b.ensureSuffixes(ev);
        try b.convertSuffixRules(ev);
        if (ev.builtin_rules and !makeflagsNoBuiltinRules(ev)) try b.addBuiltinRules(ev);
        b.db.suffixes = b.suffixes.items;
        b.db.rules = b.rules.items;
        b.db.vpaths = b.vpaths.items;
        b.db.pattern_vars = b.pattern_vars.items;
        ev.line = 0;
        if (ev.lookup("VPATH")) |v| {
            const value = if (v.recursive) try ev.expand(v.value, null) else v.value;
            b.db.vpath_dirs = try splitDirs(ev.arena, value);
        }
        if (ev.lookup(".DEFAULT_GOAL")) |v| {
            const value = if (v.recursive) try ev.expand(v.value, null) else v.value;
            var it = std.mem.tokenizeAny(u8, value, fns.whitespace);
            if (it.next()) |goal| b.db.default_goal = goal;
        }
        assert(b.db.rules.len == b.rules.items.len);
        assert(b.db.default_goal == null or b.db.default_goal.?.len > 0);
        return b.db;
    }
};

/// Replay the statements of a parsed input file. The executable uses the
/// reader instead, which also handles conditionals and `define`.
pub fn load(ev: *eval.Evaluator, mk: ast.Makefile) Error!Database {
    assert(mk.filename.len > 0);
    ev.filename = mk.filename;
    var b: Builder = .init(mk.mode, mk.filename);
    for (mk.statements) |st| try b.apply(ev, st);
    const db = try b.finish(ev);
    assert(db.rules.len <= mk.statements.len * ast.limits.names_per_line_max);
    return db;
}

/// Split a directory list on colons and white space, as GNU Make does.
pub fn splitDirs(arena: std.mem.Allocator, text: []const u8) error{OutOfMemory}![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, ": \t\n");
    while (it.next()) |dir| {
        assert(dir.len > 0);
        try out.append(arena, dir);
    }
    assert(out.items.len <= text.len);
    return out.items;
}

fn assign(ev: *eval.Evaluator, a: ast.Assignment) Error!void {
    assert(a.name.len > 0);
    const name = std.mem.trim(u8, try ev.expand(a.name, null), fns.whitespace);
    if (name.len == 0) return ev.fail("empty variable name", .{});
    const origin: ast.Origin = if (a.override) .override else .file;
    switch (a.flavor) {
        .simple => try ev.define(name, try ev.expand(a.value, null), false, origin),
        .recursive => try ev.define(name, a.value, true, origin),
        .conditional => if (ev.lookup(name) == null) try ev.define(name, a.value, true, origin),
        .append => {
            const old = ev.lookup(name) orelse return ev.define(name, a.value, true, origin);
            const add = if (old.recursive) a.value else try ev.expand(a.value, null);
            const joined = if (old.value.len == 0)
                add
            else if (add.len == 0)
                old.value
            else
                try std.mem.concat(ev.arena, u8, &.{ old.value, " ", add });
            try ev.define(name, joined, old.recursive, origin);
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
    if (targets.len == 1 and prereqs.len == 0 and order_only.len == 0 and suffixCandidate(targets[0])) {
        return b.suffix_candidates.append(ev.arena, .{
            .targets = targets,
            .prerequisites = &.{},
            .order_only = &.{},
            .recipes = r.recipes,
            .has_recipe = r.has_recipe,
            .task = r.task,
            .is_pattern = false,
            .source_line = r.line,
            .file = r.file,
            .double_colon = r.double_colon,
        });
    }
    var specials: usize = 0;
    for (targets) |t| {
        if (ast.isSpecialTarget(t)) specials += 1;
    }
    if (specials > 0) {
        if (specials != targets.len) return ev.fail("mix of special and other targets in one rule", .{});
        for (targets) |t| try addSpecial(ev, b, t, prereqs);
        return;
    }
    const is_pattern = ast.isPattern(targets[0]);
    if (is_pattern and r.double_colon) return ev.fail("double-colon pattern rules are not supported", .{});
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
        .file = r.file,
        .double_colon = r.double_colon,
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
    } else if (eql(u8, target, ".EXPORT_ALL_VARIABLES")) {
        ev.export_all = true;
    } else if (eql(u8, target, ".SUFFIXES")) {
        try b.setSuffixes(ev, prereqs);
    } else if (isIgnoredSpecial(target)) {
        // These targets change nothing in zmake. See the CLI contract spec.
    } else {
        return ev.fail("special target '{s}' is not supported", .{target});
    }
    assert(target[0] == '.');
}

fn isIgnoredSpecial(target: []const u8) bool {
    const ignored = [_][]const u8{
        ".INTERMEDIATE", ".NOTINTERMEDIATE", ".POSIX", ".LOW_RESOLUTION_TIME",
    };
    for (ignored) |name| {
        if (std.mem.eql(u8, target, name)) return true;
    }
    assert(target.len > 0 and target[0] == '.');
    return false;
}

/// A name that starts with a dot, has no `/` or `%`, and is not a special
/// target. `finish` decides whether it is a suffix rule.
fn suffixCandidate(name: []const u8) bool {
    assert(name.len > 0);
    if (name[0] != '.' or name.len < 2 or std.mem.indexOfAny(u8, name, "/%") != null) return false;
    const special = inList(&special_targets, name);
    assert(special or name[0] == '.');
    return !special;
}

/// Split `.c.o` into `.c` and `.o`, or take `.c` alone, when the list has
/// the suffixes. A double suffix comes first, as in GNU Make.
fn splitSuffixRule(list: []const []const u8, name: []const u8) ?[2][]const u8 {
    assert(name.len > 1 and name[0] == '.');
    var i: usize = 1;
    while (i < name.len) : (i += 1) {
        if (name[i] != '.') continue;
        if (inList(list, name[0..i]) and inList(list, name[i..])) return .{ name[0..i], name[i..] };
    }
    assert(i == name.len);
    return if (inList(list, name)) .{ name, "" } else null;
}

fn inList(list: []const []const u8, s: []const u8) bool {
    assert(s.len > 0);
    for (list) |item| {
        if (std.mem.eql(u8, item, s)) return true;
    }
    return false;
}

fn hasPatternRule(rules: []const ast.Rule, target: []const u8, source: []const u8) bool {
    assert(target.len > 0 and source.len > 0);
    for (rules) |r| {
        if (!r.is_pattern or r.targets.len != 1 or r.prerequisites.len != 1) continue;
        if (std.mem.eql(u8, r.targets[0], target) and std.mem.eql(u8, r.prerequisites[0], source)) return true;
    }
    return false;
}

/// `MAKEFLAGS += -r` (or `-R`, `--no-builtin-rules`) in the input file turns
/// the built-in rules off, as in GNU Make.
fn makeflagsNoBuiltinRules(ev: *const eval.Evaluator) bool {
    const v = ev.vars.get("MAKEFLAGS") orelse return false;
    if (v.origin != .file and v.origin != .override) return false;
    var it = std.mem.tokenizeAny(u8, v.value, fns.whitespace);
    var first = true;
    while (it.next()) |w| : (first = false) {
        assert(w.len > 0);
        if (std.mem.eql(u8, w, "--no-builtin-rules") or std.mem.eql(u8, w, "--no-builtin-variables")) return true;
        const letters = w[0] == '-' and w.len > 1 and w[1] != '-';
        if ((letters or (first and w[0] != '-')) and std.mem.indexOfAny(u8, w, "rR") != null) return true;
    }
    assert(it.index <= v.value.len);
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
    const suffix = try loadTest(a, ".c.o:\n\tcc -c $<\n.x.y:\n\techo\n", .legacy, &diag);
    try testing.expectEqualStrings("%.o", suffix.rules[0].targets[0]);
    try testing.expectEqualStrings("%.c", suffix.rules[0].prerequisites[0]);
    try testing.expect(suffix.rules[0].is_pattern);
    try testing.expectEqualStrings(".x.y", suffix.rules[1].targets[0]);
    try testing.expect(!suffix.rules[1].is_pattern);
    try testing.expectError(error.Eval, loadTest(a, ".ONESHELL:\n", .legacy, &diag));
    try testing.expectError(error.Eval, loadTest(a, ".PHONY all:\n", .legacy, &diag));
}

test "a line that expands to nothing is valid" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    const db = try loadTest(a, "X := 1\n$(if $(X),,$(error no X))\nall:\n", .legacy, &diag);
    try testing.expectEqualStrings("all", db.default_goal.?);
    try testing.expectError(error.Eval, loadTest(a, "$(firstword a b)\n", .legacy, &diag));
    try testing.expectEqualStrings("Makefile:1: *** missing separator.  Stop.", diag.message());
}

test "built-in rules follow the suffix list and yield to the input file" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    const count = struct {
        fn of(db: Database, target: []const u8, source: []const u8) usize {
            var n: usize = 0;
            for (db.rules) |r| {
                if (r.is_pattern and std.mem.eql(u8, r.targets[0], target) and std.mem.eql(u8, r.prerequisites[0], source)) n += 1;
            }
            return n;
        }
    }.of;
    var ev = eval.Evaluator.init(a, testing.io, std.Io.Dir.cwd(), &diag);
    ev.builtin_rules = true;
    const plain = try load(&ev, try parser.parse(a, "all:\n", "Makefile", .legacy, &diag));
    try testing.expectEqual(@as(usize, 1), count(plain, "%.o", "%.c"));
    try testing.expectEqualStrings("<builtin>", plain.rules[plain.rules.len - 1].file);
    var ev2 = eval.Evaluator.init(a, testing.io, std.Io.Dir.cwd(), &diag);
    ev2.builtin_rules = true;
    const user = try load(&ev2, try parser.parse(a, "%.o: %.c\n\techo user\n%.o: %.cc\n", "Makefile", .legacy, &diag));
    try testing.expectEqual(@as(usize, 1), count(user, "%.o", "%.c"));
    try testing.expectEqualStrings("echo user", user.rules[0].recipes[0].text);
    try testing.expectEqual(@as(usize, 1), count(user, "%.o", "%.cc"));
    var ev3 = eval.Evaluator.init(a, testing.io, std.Io.Dir.cwd(), &diag);
    ev3.builtin_rules = true;
    const cleared = try load(&ev3, try parser.parse(a, ".SUFFIXES:\n", "Makefile", .legacy, &diag));
    try testing.expectEqual(@as(usize, 0), count(cleared, "%.o", "%.c"));
    var ev4 = eval.Evaluator.init(a, testing.io, std.Io.Dir.cwd(), &diag);
    ev4.builtin_rules = true;
    const flagged = try load(&ev4, try parser.parse(a, "MAKEFLAGS += -r\n", "Makefile", .legacy, &diag));
    try testing.expectEqual(@as(usize, 0), count(flagged, "%.o", "%.c"));
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
