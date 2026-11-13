//! Dependency graph. `build` resolves each goal through explicit rules, pattern
//! rules and existing files. A three-color depth-first search on an explicit
//! stack detects cycles and gives a topological order (ADR-0003, rule R1).

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const ast = @import("ast.zig");
const fns = @import("functions.zig");
const database = @import("database.zig");
const Diagnostic = @import("diag.zig").Diagnostic;

pub const Error = error{ Graph, OutOfMemory };
pub const NodeId = u32;

/// One `target:: prerequisites` rule. The executor decides and runs each one
/// on its own, in file order.
pub const Instance = struct {
    prerequisites: []const []const u8,
    recipes: []const ast.RecipeLine,
    line: u32,
    file: []const u8,
    /// The stem of a static pattern rule (`$*`), else empty.
    stem: []const u8 = "",
    order_only: []const []const u8 = &.{},
};

pub const Node = struct {
    name: []const u8,
    kind: ast.TargetKind,
    /// The normal prerequisites in rule order, with duplicates (`$+`).
    prerequisites: []const []const u8,
    order_only: []const []const u8,
    /// The nodes of all prerequisites, without duplicates. Set by the search.
    deps: []const NodeId = &.{},
    recipes: []const ast.RecipeLine,
    stem: []const u8,
    /// The line of the rule that makes the target, or 0 when no rule exists.
    line: u32,
    /// The input file of that rule, or empty when no rule exists.
    file: []const u8 = "",
    /// The path where directory search found the file, or empty when the
    /// file is in the working directory or missing. See `filePath`.
    path: []const u8 = "",
    /// The node that first needs this node in the search. Its target-specific
    /// variables are in effect here too. Null for a goal.
    parent: ?NodeId = null,
    /// The double-colon rules of the target, or empty. `recipes` is then empty.
    instances: []const Instance = &.{},

    /// The path of the file on disk: the search result, else the name.
    pub fn filePath(node: *const Node) []const u8 {
        assert(node.name.len > 0);
        const p = if (node.path.len > 0) node.path else node.name;
        assert(p.len > 0);
        return p;
    }
};

pub const Graph = struct {
    nodes: []const Node,
    /// Each node after its prerequisites.
    order: []const NodeId,
    goals: []const NodeId,
    index: std.StringHashMapUnmanaged(NodeId),
    /// GNU-style warnings, for example an overriding recipe.
    warnings: []const []const u8,
};

const Explicit = struct {
    prerequisites: std.ArrayList([]const u8) = .empty,
    order_only: std.ArrayList([]const u8) = .empty,
    recipe: ?*const ast.Rule = null,
    task: bool = false,
    line: u32,
    file: []const u8,
    /// True after a `::` rule, false after a `:` rule, null before either.
    double_colon: ?bool = null,
    instances: std.ArrayList(Instance) = .empty,
    /// The stem from a static pattern rule of the target, else null.
    stem: ?[]const u8 = null,
};

const Match = struct {
    rule: *const ast.Rule,
    stem: []const u8,
    prerequisites: []const []const u8,
    /// The order-only prerequisites of the rule, with the stem applied.
    order_only: []const []const u8,
};

const Color = enum(u2) { white, gray, black };

const Builder = struct {
    arena: std.mem.Allocator,
    io: Io,
    dir: Io.Dir,
    db: *const database.Database,
    diag: *Diagnostic,
    explicit: std.StringHashMapUnmanaged(Explicit) = .empty,
    patterns: std.ArrayList(*const ast.Rule) = .empty,
    index: std.StringHashMapUnmanaged(NodeId) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    colors: std.ArrayList(Color) = .empty,
    warnings: std.ArrayList([]const u8) = .empty,
    goal_ids: std.ArrayList(NodeId) = .empty,

    fn fail(b: *Builder, comptime fmt: []const u8, args: anytype) Error {
        comptime assert(fmt.len > 0);
        b.diag.set(fmt, args);
        assert(b.diag.len > 0);
        return error.Graph;
    }
};

pub fn build(
    arena: std.mem.Allocator,
    io: Io,
    dir: Io.Dir,
    db: *const database.Database,
    goal_names: []const []const u8,
    diag: *Diagnostic,
) Error!Graph {
    var b: Builder = .{ .arena = arena, .io = io, .dir = dir, .db = db, .diag = diag };
    try indexRules(&b);
    const names: []const []const u8 = if (goal_names.len > 0) goal_names else blk: {
        const goal = db.default_goal orelse return b.fail("*** No targets.  Stop.", .{});
        break :blk &.{goal};
    };
    var goals: std.ArrayList(NodeId) = .empty;
    var order: std.ArrayList(NodeId) = .empty;
    for (names) |name| {
        assert(name.len > 0);
        const id = try nodeFor(&b, name, null);
        try goals.append(arena, id);
        try b.goal_ids.append(arena, id);
        try search(&b, id, &order);
    }
    assert(order.items.len == countBlack(&b));
    return .{ .nodes = b.nodes.items, .order = order.items, .goals = goals.items, .index = b.index, .warnings = b.warnings.items };
}

fn countBlack(b: *const Builder) usize {
    var n: usize = 0;
    for (b.colors.items) |c| n += @intFromBool(c == .black);
    assert(n <= b.nodes.items.len);
    return n;
}

/// Merge the explicit rules per target and keep the pattern rules in order.
fn indexRules(b: *Builder) Error!void {
    for (b.db.rules) |*rule| {
        assert(rule.targets.len > 0);
        if (rule.is_pattern) {
            if (rule.has_recipe) try b.patterns.append(b.arena, rule);
            continue;
        }
        for (rule.targets) |t| {
            const gop = try b.explicit.getOrPut(b.arena, t);
            if (!gop.found_existing) gop.value_ptr.* = .{ .line = rule.source_line, .file = rule.file };
            const e = gop.value_ptr;
            if (e.double_colon) |dc| {
                if (dc != rule.double_colon) {
                    return b.fail("{s}:{d}: *** target file '{s}' has both : and :: entries.  Stop.", .{ rule.file, rule.source_line, t });
                }
            }
            e.double_colon = rule.double_colon;
            try e.prerequisites.appendSlice(b.arena, rule.prerequisites);
            try e.order_only.appendSlice(b.arena, rule.order_only);
            e.task = e.task or rule.task;
            if (rule.stem) |s| e.stem = s;
            if (rule.double_colon) {
                try e.instances.append(b.arena, .{ .prerequisites = rule.prerequisites, .recipes = rule.recipes, .line = rule.source_line, .file = rule.file, .stem = rule.stem orelse "", .order_only = rule.order_only });
                continue;
            }
            if (rule.has_recipe) {
                if (e.recipe) |old| try warnOverride(b, t, old, rule);
                e.recipe = rule;
            }
        }
    }
    assert(b.patterns.items.len <= b.db.rules.len);
}

fn warnOverride(b: *Builder, target: []const u8, old: *const ast.Rule, new: *const ast.Rule) Error!void {
    assert(old.has_recipe and new.has_recipe);
    try b.warnings.append(b.arena, try std.fmt.allocPrint(b.arena, "{s}:{d}: warning: overriding recipe for target '{s}'", .{ new.file, recipeLine(new), target }));
    try b.warnings.append(b.arena, try std.fmt.allocPrint(b.arena, "{s}:{d}: warning: ignoring old recipe for target '{s}'", .{ old.file, recipeLine(old), target }));
    assert(b.warnings.items.len >= 2);
}

/// GNU Make reports the line of the first recipe line, or of the rule for an empty recipe.
fn recipeLine(rule: *const ast.Rule) u32 {
    assert(rule.has_recipe);
    const line = if (rule.recipes.len > 0) rule.recipes[0].line else rule.source_line;
    assert(line >= rule.source_line);
    return line;
}

/// Return the node for `name`. Resolve its rule when the node is new.
fn nodeFor(b: *Builder, name: []const u8, needed_by: ?[]const u8) Error!NodeId {
    assert(name.len > 0);
    if (b.index.get(name)) |id| return id;
    if (b.nodes.items.len >= ast.limits.graph_nodes_max) {
        return b.fail("*** more than {d} targets.  Stop.", .{ast.limits.graph_nodes_max});
    }
    const node = try resolve(b, name, needed_by);
    const id: NodeId = @intCast(b.nodes.items.len);
    try b.nodes.append(b.arena, node);
    try b.colors.append(b.arena, .white);
    try b.index.put(b.arena, name, id);
    assert(b.nodes.items.len == b.colors.items.len);
    assert(b.index.get(name).? == id);
    return id;
}

/// Find the rule that makes `name`: an explicit rule (with a pattern rule for a
/// missing recipe), a pattern rule, or an existing file.
fn resolve(b: *Builder, name: []const u8, needed_by: ?[]const u8) Error!Node {
    assert(name.len > 0);
    assert(!b.index.contains(name));
    const phony = b.db.phony.contains(name);
    if (b.explicit.getPtr(name)) |e| {
        const double_colon = e.double_colon orelse false;
        const match = if (e.recipe == null and !phony and !double_colon) try findPattern(b, name) else null;
        var node = try explicitNode(b, name, e, match);
        if (double_colon) try addInstances(b, &node, e);
        if (!phony) node.path = try searchPath(b, name);
        return node;
    }
    if (!phony) {
        if (try findPattern(b, name)) |m| {
            var node = patternNode(b, name, m);
            node.path = try searchPath(b, name);
            return node;
        }
    }
    const found = if (phony) null else try locate(b, name);
    if (phony or found != null) {
        const kind = classifyNode(b, name, false, false, false, &.{});
        const path = if (found) |f| (if (f.ptr == name.ptr) "" else f) else "";
        return .{ .name = name, .kind = kind, .prerequisites = &.{}, .order_only = &.{}, .recipes = &.{}, .stem = "", .line = 0, .path = path };
    }
    if (needed_by) |parent| {
        return b.fail("*** No rule to make target '{s}', needed by '{s}'.  Stop.", .{ name, parent });
    }
    return b.fail("*** No rule to make target '{s}'.  Stop.", .{name});
}

fn explicitNode(b: *Builder, name: []const u8, e: *const Explicit, match: ?Match) Error!Node {
    assert(name.len > 0);
    var prereqs: []const []const u8 = e.prerequisites.items;
    var recipes: []const ast.RecipeLine = if (e.recipe) |r| r.recipes else &.{};
    var stem: []const u8 = e.stem orelse "";
    var order_only: []const []const u8 = e.order_only.items;
    var line = if (e.recipe) |r| r.source_line else e.line;
    var file = if (e.recipe) |r| r.file else e.file;
    if (match) |m| {
        // The pattern prerequisites come first, so `$<` is the pattern source.
        prereqs = try std.mem.concat(b.arena, []const u8, &.{ m.prerequisites, prereqs });
        order_only = try std.mem.concat(b.arena, []const u8, &.{ m.order_only, order_only });
        recipes = m.rule.recipes;
        stem = m.stem;
        line = m.rule.source_line;
        file = m.rule.file;
    }
    const kind = classifyNode(b, name, true, e.task, match != null, recipes);
    assert(line > 0);
    return .{ .name = name, .kind = kind, .prerequisites = prereqs, .order_only = order_only, .recipes = recipes, .stem = stem, .line = line, .file = file };
}

/// Give a double-colon target its rules. The kind follows all their recipes.
fn addInstances(b: *Builder, node: *Node, e: *const Explicit) Error!void {
    assert(e.instances.items.len > 0);
    var all: std.ArrayList(ast.RecipeLine) = .empty;
    for (e.instances.items) |inst| try all.appendSlice(b.arena, inst.recipes);
    node.instances = e.instances.items;
    node.kind = classifyNode(b, node.name, true, e.task, false, all.items);
    node.line = e.instances.items[0].line;
    node.file = e.instances.items[0].file;
    assert(node.recipes.len == 0);
}

fn patternNode(b: *Builder, name: []const u8, m: Match) Node {
    assert(m.rule.is_pattern and m.rule.has_recipe);
    const kind = classifyNode(b, name, true, false, true, m.rule.recipes);
    assert(kind == .file or kind == .explicit_phony);
    return .{ .name = name, .kind = kind, .prerequisites = m.prerequisites, .order_only = m.order_only, .recipes = m.rule.recipes, .stem = m.stem, .line = m.rule.source_line, .file = m.rule.file };
}

fn classifyNode(b: *Builder, name: []const u8, has_rule: bool, task: bool, from_pattern: bool, recipes: []const ast.RecipeLine) ast.TargetKind {
    assert(name.len > 0);
    const facts: database.TargetFacts = .{ .has_rule = has_rule, .task = task, .from_pattern = from_pattern, .recipes = recipes };
    const kind = database.classify(b.db, name, facts);
    assert(b.db.mode == .modern or kind != .inferred_phony);
    return kind;
}

fn exists(b: *Builder, name: []const u8) Error!bool {
    assert(name.len > 0);
    if (b.dir.access(b.io, name, .{})) |_| return true else |err| switch (err) {
        error.FileNotFound => return false,
        else => return b.fail("*** {s}: {s}.  Stop.", .{ name, @errorName(err) }),
    }
}

/// True when `name` exists (also through directory search), has an explicit
/// rule or is phony.
fn known(b: *Builder, name: []const u8) Error!bool {
    assert(name.len > 0);
    if (b.explicit.contains(name) or b.db.phony.contains(name)) return true;
    return (try locate(b, name)) != null;
}

/// Find `name` in the working directory, then in the `vpath` directories
/// whose pattern matches, then in the `VPATH` directories. Return the path.
fn locate(b: *Builder, name: []const u8) Error!?[]const u8 {
    assert(name.len > 0);
    if (try exists(b, name)) return name;
    if (name[0] == '/') return null;
    for (b.db.vpaths) |v| {
        if (fns.matchPattern(v.pattern, name) == null) continue;
        if (try firstIn(b, v.dirs, name)) |p| return p;
    }
    const found = try firstIn(b, b.db.vpath_dirs, name);
    assert(found == null or found.?.len > name.len);
    return found;
}

fn firstIn(b: *Builder, dirs: []const []const u8, name: []const u8) Error!?[]const u8 {
    assert(name.len > 0);
    for (dirs) |dir| {
        const sep: []const u8 = if (dir[dir.len - 1] == '/') "" else "/";
        const candidate = try std.mem.concat(b.arena, u8, &.{ dir, sep, name });
        if (try exists(b, candidate)) return candidate;
    }
    assert(dirs.len <= ast.limits.names_per_line_max);
    return null;
}

/// The search path of a target, or empty when it is in the working directory or missing.
fn searchPath(b: *Builder, name: []const u8) Error![]const u8 {
    assert(name.len > 0);
    const found = try locate(b, name) orelse return "";
    assert(found.len >= name.len);
    return if (found.ptr == name.ptr) "" else found;
}

/// Pick the viable pattern rule with the shortest stem; the first rule wins a tie.
/// A prerequisite is viable when it is known, or when a second pattern rule can
/// make it from known files (one level of chaining).
fn findPattern(b: *Builder, name: []const u8) Error!?Match {
    assert(name.len > 0);
    // GNU Make first looks for a rule whose prerequisites exist or have rules.
    // Only when none applies does it try rules that need a chain.
    if (try findDirectPattern(b, name, null)) |m| return m;
    const specific = specificType(b, name);
    var best: ?Match = null;
    for (b.patterns.items) |rule| {
        if (specific and matchAnything(rule)) continue;
        const m = try matchRule(b, rule, name) orelse continue;
        if (best != null and m.stem.len >= best.?.stem.len) continue;
        if (try viableChain(b, m, rule)) best = m;
    }
    assert(best == null or best.?.rule.is_pattern);
    return best;
}

/// A rule with the target `%` alone, such as the built-in `%: %.o`.
fn matchAnything(rule: *const ast.Rule) bool {
    assert(rule.is_pattern);
    for (rule.targets) |t| {
        if (std.mem.eql(u8, t, "%")) return true;
    }
    assert(rule.targets.len > 0);
    return false;
}

/// True when `name` has a known suffix, or when a pattern target other than
/// `%` matches it. GNU Make does not use a match-anything rule for such a name,
/// so `%: %.o` cannot make `main.c`.
fn specificType(b: *const Builder, name: []const u8) bool {
    assert(name.len > 0);
    for (b.db.suffixes) |s| {
        if (name.len > s.len and std.mem.endsWith(u8, name, s)) return true;
    }
    for (b.patterns.items) |rule| {
        for (rule.targets) |t| {
            if (!std.mem.eql(u8, t, "%") and fns.matchPattern(t, name) != null) return true;
        }
    }
    assert(b.patterns.items.len <= b.db.rules.len);
    return false;
}

/// Like `findPattern`, but each prerequisite must be known. `skip` is the rule
/// that asks for a prerequisite of its own, so a rule cannot chain to itself.
/// A match-anything rule cannot make the prerequisite of another rule, and it
/// cannot make a name of a specific type.
fn findDirectPattern(b: *Builder, name: []const u8, skip: ?*const ast.Rule) Error!?Match {
    assert(name.len > 0);
    const no_match_anything = skip != null or specificType(b, name);
    var best: ?Match = null;
    for (b.patterns.items) |rule| {
        if (skip != null and rule == skip.?) continue;
        if (no_match_anything and matchAnything(rule)) continue;
        const m = try matchRule(b, rule, name) orelse continue;
        if (best != null and m.stem.len >= best.?.stem.len) continue;
        if (try allKnown(b, m.prerequisites) and try allKnown(b, m.order_only)) best = m;
    }
    assert(best == null or skip == null or best.?.rule != skip.?);
    return best;
}

/// Match `name` against each target pattern of `rule`. A pattern without `/`
/// matches the file part of the name, and the directory joins the stem.
fn matchRule(b: *Builder, rule: *const ast.Rule, name: []const u8) Error!?Match {
    assert(rule.is_pattern);
    for (rule.targets) |pattern| {
        const slash = std.mem.lastIndexOfScalar(u8, name, '/');
        const use_dir = std.mem.indexOfScalar(u8, pattern, '/') == null and slash != null;
        const subject = if (use_dir) name[slash.? + 1 ..] else name;
        if (subject.len == 0) continue;
        const part = fns.matchPattern(pattern, subject) orelse continue;
        const stem = if (use_dir) try std.mem.concat(b.arena, u8, &.{ name[0 .. slash.? + 1], part }) else part;
        const prereqs = try fns.applyStemAll(b.arena, rule.prerequisites, stem);
        const order_only = try fns.applyStemAll(b.arena, rule.order_only, stem);
        assert(prereqs.len == rule.prerequisites.len);
        return .{ .rule = rule, .stem = stem, .prerequisites = prereqs, .order_only = order_only };
    }
    return null;
}

/// True when each prerequisite of `m`, normal and order-only, is known or can
/// come from a second pattern rule. GNU Make also checks the order-only ones.
fn viableChain(b: *Builder, m: Match, rule: *const ast.Rule) Error!bool {
    assert(m.rule == rule);
    for ([_][]const []const u8{ m.prerequisites, m.order_only }) |list| {
        for (list) |p| {
            assert(p.len > 0);
            if (try known(b, p)) continue;
            if (try findDirectPattern(b, p, rule) == null) return false;
        }
    }
    return true;
}

fn allKnown(b: *Builder, names: []const []const u8) Error!bool {
    assert(b.nodes.items.len <= ast.limits.graph_nodes_max);
    for (names) |p| {
        assert(p.len > 0);
        if (!try known(b, p)) return false;
    }
    return true;
}

const Visit = struct { id: NodeId, next: u32 };

/// Depth-first search from `root` on an explicit stack. Append each node to
/// `order` after its prerequisites. A gray node on the path is a cycle.
fn search(b: *Builder, root: NodeId, order: *std.ArrayList(NodeId)) Error!void {
    assert(root < b.nodes.items.len);
    if (b.colors.items[root] != .white) return;
    var stack: std.ArrayList(Visit) = .empty;
    try stack.append(b.arena, .{ .id = root, .next = 0 });
    b.colors.items[root] = .gray;
    var steps: u64 = 0;
    const max_steps: u64 = @as(u64, ast.limits.graph_nodes_max) * ast.limits.names_per_line_max;
    while (stack.items.len > 0 and steps < max_steps) : (steps += 1) {
        const top = &stack.items[stack.items.len - 1];
        assert(b.colors.items[top.id] == .gray);
        const node = b.nodes.items[top.id];
        const total = node.prerequisites.len + node.order_only.len;
        if (top.next == total) {
            try finishNode(b, top.id);
            b.colors.items[top.id] = .black;
            try order.append(b.arena, top.id);
            stack.items.len -= 1;
            continue;
        }
        const i = top.next;
        top.next += 1;
        const child_name = if (i < node.prerequisites.len) node.prerequisites[i] else node.order_only[i - node.prerequisites.len];
        const child = try nodeFor(b, child_name, node.name);
        switch (b.colors.items[child]) {
            .black => {},
            .gray => return cycleError(b, stack.items, child),
            .white => {
                if (stack.items.len >= ast.limits.graph_depth_max) {
                    return b.fail("*** prerequisites nest more than {d} levels.  Stop.", .{ast.limits.graph_depth_max});
                }
                if (b.nodes.items[child].parent == null and !isGoal(b, child)) b.nodes.items[child].parent = top.id;
                b.colors.items[child] = .gray;
                try stack.append(b.arena, .{ .id = child, .next = 0 });
            },
        }
    }
    assert(stack.items.len == 0);
}

fn isGoal(b: *const Builder, id: NodeId) bool {
    assert(id < b.nodes.items.len);
    const goal = std.mem.indexOfScalar(NodeId, b.goal_ids.items, id) != null;
    assert(!goal or b.goal_ids.items.len > 0);
    return goal;
}

/// Record the deduplicated prerequisite nodes of a finished node.
fn finishNode(b: *Builder, id: NodeId) Error!void {
    assert(b.colors.items[id] == .gray);
    const node = &b.nodes.items[id];
    var deps: std.ArrayList(NodeId) = .empty;
    for ([_][]const []const u8{ node.prerequisites, node.order_only }) |list| {
        for (list) |name| {
            const dep = b.index.get(name).?;
            assert(b.colors.items[dep] == .black);
            if (std.mem.indexOfScalar(NodeId, deps.items, dep) == null) try deps.append(b.arena, dep);
        }
    }
    node.deps = deps.items;
    assert(node.deps.len <= node.prerequisites.len + node.order_only.len);
}

fn cycleError(b: *Builder, path: []const Visit, back: NodeId) Error {
    assert(path.len > 0);
    var text: std.ArrayList(u8) = .empty;
    var started = false;
    for (path) |v| {
        if (v.id == back) started = true;
        if (!started) continue;
        const n = b.nodes.items[v.id];
        text.print(b.arena, "{s} ({s}:{d}) -> ", .{ n.name, n.file, n.line }) catch return error.OutOfMemory;
    }
    assert(started);
    text.appendSlice(b.arena, b.nodes.items[back].name) catch return error.OutOfMemory;
    return b.fail("*** Circular dependency: {s}.  Stop.", .{text.items});
}

const testing = std.testing;
const parser = @import("parser.zig");
const eval = @import("eval.zig");

fn buildTest(arena: std.mem.Allocator, dir: Io.Dir, src: []const u8, mode: ast.SyntaxMode, goals: []const []const u8, diag: *Diagnostic) !Graph {
    const mk = try parser.parse(arena, src, "Makefile", mode, diag);
    var ev = eval.Evaluator.init(arena, testing.io, dir, diag);
    const db = try arena.create(database.Database);
    db.* = try database.load(&ev, mk);
    return build(arena, testing.io, dir, db, goals, diag);
}

fn testNames(arena: std.mem.Allocator, g: Graph) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (g.order) |id| try fns.appendWord(arena, &out, g.nodes[id].name);
    return out.items;
}

test "topological order with a diamond" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    const src = ".PHONY: a b c d\na: b c\nb: d\nc: d\nd:\n";
    const g = try buildTest(a, Io.Dir.cwd(), src, .legacy, &.{}, &diag);
    try testing.expectEqualStrings("d b c a", try testNames(a, g));
    try testing.expectEqual(@as(usize, 2), g.nodes[g.goals[0]].deps.len);
}

test "cycle error shows the path with lines" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    try testing.expectError(error.Graph, buildTest(arena.allocator(), Io.Dir.cwd(), "a: b\n\techo a\nb: a\n\techo b\n", .legacy, &.{}, &diag));
    try testing.expectEqualStrings("*** Circular dependency: a (Makefile:1) -> b (Makefile:3) -> a.  Stop.", diag.message());
    try testing.expectError(error.Graph, buildTest(arena.allocator(), Io.Dir.cwd(), "x: x\n", .legacy, &.{}, &diag));
}

test "missing prerequisite and missing goal" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    try testing.expectError(error.Graph, buildTest(a, Io.Dir.cwd(), "app: nope.c\n\tcc\n", .legacy, &.{}, &diag));
    try testing.expectEqualStrings("*** No rule to make target 'nope.c', needed by 'app'.  Stop.", diag.message());
    try testing.expectError(error.Graph, buildTest(a, Io.Dir.cwd(), "app:\n", .legacy, &.{"other"}, &diag));
    try testing.expectEqualStrings("*** No rule to make target 'other'.  Stop.", diag.message());
    try testing.expectError(error.Graph, buildTest(a, Io.Dir.cwd(), "X = 1\n", .legacy, &.{}, &diag));
    try testing.expectEqualStrings("*** No targets.  Stop.", diag.message());
}

test "pattern rules: stem, explicit prerequisites and shortest stem" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    for ([_][]const u8{ "main.c", "util.c", "main.h", "src/lib/x.c" }) |f| {
        try tmp.dir.createDirPath(testing.io, std.fs.path.dirname(f) orelse ".");
        try tmp.dir.writeFile(testing.io, .{ .sub_path = f, .data = "" });
    }
    const src = "app: main.o util.o src/lib/x.o\n\tcc -o $@ $^\nmain.o: main.h\n%.o: %.c\n\tcc -c $<\nsrc/%.o: src/%.c\n\tcc -c $< # src\n";
    const g = try buildTest(a, tmp.dir, src, .legacy, &.{}, &diag);
    try testing.expectEqualStrings("main.c main.h main.o util.c util.o src/lib/x.c src/lib/x.o app", try testNames(a, g));
    const app = g.nodes[g.goals[0]];
    const main_o = g.nodes[app.deps[0]];
    try testing.expectEqualStrings("main.o", main_o.name);
    try testing.expectEqualStrings("main.c", main_o.prerequisites[0]);
    try testing.expectEqualStrings("main.h", main_o.prerequisites[1]);
    try testing.expectEqualStrings("main", main_o.stem);
    const x_o = g.nodes[app.deps[2]];
    try testing.expectEqualStrings("lib/x", x_o.stem);
    try testing.expectEqual(@as(u32, 6), x_o.line);
}

test "pattern rules keep order-only prerequisites (ISSUE-007)" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "src");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "src/main.c", .data = "" });
    const src = "app: obj/main.o\n\tcc -o $@ $^\nobj/%.o: src/%.c | obj %.dep\n\tcc -c $< -o $@\nobj:\n\tmkdir -p $@\n%.dep:\n\ttouch $@\n";
    const g = try buildTest(a, tmp.dir, src, .legacy, &.{}, &diag);
    try testing.expectEqualStrings("src/main.c obj main.dep obj/main.o app", try testNames(a, g));
    const obj = g.nodes[g.nodes[g.goals[0]].deps[0]];
    try testing.expectEqual(@as(usize, 2), obj.order_only.len);
    try testing.expectEqualStrings("main.dep", obj.order_only[1]);
    try testing.expectEqual(@as(usize, 1), obj.prerequisites.len);
}

test "directory search finds prerequisites through vpath and VPATH" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    for ([_][]const u8{ "src/main.c", "inc/x.h", "lib/libz.a" }) |f| {
        try tmp.dir.createDirPath(testing.io, std.fs.path.dirname(f).?);
        try tmp.dir.writeFile(testing.io, .{ .sub_path = f, .data = "" });
    }
    const mk = try parser.parse(a, "app: main.o libz.a\n\tcc -o $@ $^\n%.o: %.c x.h\n\tcc -c $<\n", "Makefile", .legacy, &diag);
    var ev = eval.Evaluator.init(a, testing.io, tmp.dir, &diag);
    try ev.define("VPATH", "nope:src", false, .file);
    var b: database.Builder = .init(.legacy, "Makefile");
    for (mk.statements) |st| try b.apply(&ev, st);
    try b.vpath(&ev, "%.h", &.{"inc"});
    try b.vpath(&ev, "%.a", &.{"lib"});
    const db = try a.create(database.Database);
    db.* = try b.finish(&ev);
    const g = try build(a, testing.io, tmp.dir, db, &.{}, &diag);
    try testing.expectEqualStrings("src/main.c", g.nodes[g.index.get("main.c").?].filePath());
    try testing.expectEqualStrings("inc/x.h", g.nodes[g.index.get("x.h").?].filePath());
    try testing.expectEqualStrings("lib/libz.a", g.nodes[g.index.get("libz.a").?].filePath());
    try testing.expectEqualStrings("main.o", g.nodes[g.index.get("main.o").?].filePath());
    try b.vpath(&ev, "%.h", &.{});
    try testing.expectEqual(@as(usize, 1), b.vpaths.items.len);
}

test "double-colon rules keep one instance per rule" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    const src = ".PHONY: a.in b.in\nout:: a.in\n\techo 1\nout:: b.in\n\techo 2\na.in:\nb.in:\n";
    const g = try buildTest(a, Io.Dir.cwd(), src, .legacy, &.{}, &diag);
    const out = g.nodes[g.goals[0]];
    try testing.expectEqual(@as(usize, 2), out.instances.len);
    try testing.expectEqualStrings("b.in", out.instances[1].prerequisites[0]);
    try testing.expectEqual(@as(usize, 2), out.deps.len);
    try testing.expectEqual(@as(usize, 0), out.recipes.len);
    try testing.expectError(error.Graph, buildTest(a, Io.Dir.cwd(), "x: a\n\techo\nx:: b\n\techo\n", .legacy, &.{}, &diag));
    try testing.expectEqualStrings("Makefile:3: *** target file 'x' has both : and :: entries.  Stop.", diag.message());
}

test "modern mode classifies graph nodes" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "build");
    const src = "build:\n    echo b\n@deploy: build app\n    echo d\napp:\n    cc -o $@\n";
    const g = try buildTest(a, tmp.dir, src, .modern, &.{"deploy"}, &diag);
    try testing.expectEqualStrings("build app deploy", try testNames(a, g));
    try testing.expectEqual(ast.TargetKind.inferred_phony, g.nodes[g.order[0]].kind);
    try testing.expectEqual(ast.TargetKind.file, g.nodes[g.order[1]].kind);
    try testing.expectEqual(ast.TargetKind.explicit_phony, g.nodes[g.order[2]].kind);
}

test "overriding recipe warnings and merged prerequisites" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    const src = ".PHONY: a b c\na: b\n\techo 1\na: c\n\techo 2\nb:\nc:\n";
    const g = try buildTest(a, Io.Dir.cwd(), src, .legacy, &.{}, &diag);
    try testing.expectEqual(@as(usize, 2), g.warnings.len);
    try testing.expectEqualStrings("Makefile:5: warning: overriding recipe for target 'a'", g.warnings[0]);
    try testing.expectEqualStrings("Makefile:3: warning: ignoring old recipe for target 'a'", g.warnings[1]);
    const node = g.nodes[g.goals[0]];
    try testing.expectEqual(@as(usize, 2), node.prerequisites.len);
    try testing.expectEqualStrings("echo 2", node.recipes[0].text);
}
