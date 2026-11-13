//! Target contexts: the target-specific and pattern-specific variables that
//! are in effect for each node. A node inherits the layers of the node that
//! first needs it (`dag.Node.parent`), minus the `private` variables, and adds
//! one layer with its own pattern-specific and target-specific assignments.
//!
//! `build` visits the nodes in reverse topological order, so a parent always
//! has its context before its prerequisites. No function calls itself
//! (ADR-0003, rule R1). See ADR-0016.

const std = @import("std");
const assert = std.debug.assert;
const ast = @import("ast.zig");
const fns = @import("functions.zig");
const eval = @import("eval.zig");
const dag = @import("dag.zig");
const database = @import("database.zig");

const Context = []const *const eval.Layer;

/// Return the layers of each node, or an empty slice when the input file has
/// no target-specific or pattern-specific variables.
pub fn build(arena: std.mem.Allocator, ev: *eval.Evaluator, graph: *const dag.Graph, db: *const database.Database) eval.Error![]const Context {
    if (db.target_vars.count() == 0 and db.pattern_vars.len == 0) return &.{};
    const contexts = try arena.alloc(Context, graph.nodes.len);
    @memset(contexts, &.{});
    var i = graph.order.len;
    while (i > 0) {
        i -= 1;
        const id = graph.order[i];
        const node = graph.nodes[id];
        const inherited = if (node.parent) |p| try inheritable(arena, contexts[p]) else &.{};
        contexts[id] = try withOwnLayer(arena, ev, db, node, inherited);
    }
    ev.layers = &.{};
    assert(contexts.len == graph.nodes.len);
    assert(i == 0);
    return contexts;
}

/// The layers of a parent without its `private` variables.
fn inheritable(arena: std.mem.Allocator, ctx: Context) error{OutOfMemory}!Context {
    var out: std.ArrayList(*const eval.Layer) = .empty;
    for (ctx) |layer| {
        var private: usize = 0;
        var it = layer.iterator();
        while (it.next()) |e| private += @intFromBool(e.value_ptr.private);
        if (private == 0) {
            try out.append(arena, layer);
            continue;
        }
        const copy = try arena.create(eval.Layer);
        copy.* = .empty;
        it = layer.iterator();
        while (it.next()) |e| {
            if (!e.value_ptr.private) try copy.put(arena, e.key_ptr.*, e.value_ptr.*);
        }
        try out.append(arena, copy);
    }
    assert(out.items.len == ctx.len);
    return out.items;
}

/// Add the layer of `node`: the matching pattern-specific assignments, longer
/// stems first, then the target-specific assignments, in file order.
fn withOwnLayer(arena: std.mem.Allocator, ev: *eval.Evaluator, db: *const database.Database, node: dag.Node, inherited: Context) eval.Error!Context {
    const patterns = try matchingPatterns(arena, db, node.name);
    const own: []const database.TargetAssign = if (db.target_vars.get(node.name)) |list| list.items else &.{};
    if (patterns.len == 0 and own.len == 0) return inherited;
    const layer = try arena.create(eval.Layer);
    layer.* = .empty;
    const ctx = try std.mem.concat(arena, *const eval.Layer, &.{ inherited, &.{layer} });
    ev.layers = ctx;
    for (patterns) |pa| try apply(ev, layer, pa.assign);
    for (own) |a| try apply(ev, layer, a);
    assert(ctx.len == inherited.len + 1);
    assert(ctx[ctx.len - 1] == layer);
    return ctx;
}

/// The pattern-specific assignments whose pattern matches `name`. GNU Make
/// applies a longer stem first, so a more specific pattern wins.
fn matchingPatterns(arena: std.mem.Allocator, db: *const database.Database, name: []const u8) error{OutOfMemory}![]const database.PatternAssign {
    assert(name.len > 0);
    var out: std.ArrayList(database.PatternAssign) = .empty;
    var stems: std.ArrayList(usize) = .empty;
    for (db.pattern_vars) |pa| {
        const stem = fns.matchPattern(pa.pattern, name) orelse continue;
        // Insertion sort: longer stems first, file order within one length.
        var at = out.items.len;
        while (at > 0 and stems.items[at - 1] < stem.len) at -= 1;
        try out.insert(arena, at, pa);
        try stems.insert(arena, at, stem.len);
    }
    assert(out.items.len == stems.items.len);
    return out.items;
}

/// Apply one assignment to `layer`. `ev.layers` ends with `layer`, so `lookup`
/// sees the inherited value and the assignments before this one. Without
/// `override`, a command-line variable wins, as in GNU Make.
fn apply(ev: *eval.Evaluator, layer: *eval.Layer, ta: database.TargetAssign) eval.Error!void {
    const a = ta.assignment;
    assert(a.name.len > 0);
    ev.line = a.line;
    const base = ev.lookup(a.name);
    if (base) |b| {
        if (b.origin == .command_line and !a.override) return;
    }
    const origin: ast.Origin = if (a.override) .override else .file;
    var v: ast.Variable = .{ .value = a.value, .recursive = true, .origin = origin, .private = ta.private, .exported = ta.exported };
    switch (a.flavor) {
        .recursive => {},
        .simple => {
            v.value = try ev.expand(a.value, null);
            v.recursive = false;
        },
        .conditional => if (base != null) return,
        .append => if (base) |b| {
            v.recursive = b.recursive;
            const add = if (b.recursive) a.value else try ev.expand(a.value, null);
            v.value = if (b.value.len == 0) add else try std.mem.concat(ev.arena, u8, &.{ b.value, " ", add });
        },
    }
    try layer.put(ev.arena, a.name, v);
    assert(layer.contains(a.name));
}

const testing = std.testing;
const reader = @import("reader.zig");
const Diagnostic = @import("diag.zig").Diagnostic;

test "contexts inherit, append, respect private and the command line" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const a = arena.allocator();
    var ev = eval.Evaluator.init(a, testing.io, std.Io.Dir.cwd(), &diag);
    try ev.define("CLI", "cmd", false, .command_line);
    const src = ".PHONY: app lib.o\nCFLAGS = -O2\napp: CFLAGS += -g\napp: private SECRET = s\n" ++
        "app: CLI = file\napp: lib.o\n\techo\nlib.o: MODE = own\n%.o: CFLAGS += -fpic\nlib.o:\n\techo\n";
    const db = try a.create(database.Database);
    db.* = try reader.read(&ev, src, "Makefile", .legacy, &diag);
    const g = try a.create(dag.Graph);
    g.* = try dag.build(a, testing.io, std.Io.Dir.cwd(), db, &.{"app"}, &diag);
    const ctx = try build(a, &ev, g, db);
    const app = g.index.get("app").?;
    const lib = g.index.get("lib.o").?;
    try testing.expectEqual(app, g.nodes[lib].parent.?);
    ev.layers = ctx[app];
    try testing.expectEqualStrings("-O2 -g", try ev.expand("$(CFLAGS)", null));
    try testing.expectEqualStrings("s cmd", try ev.expand("$(SECRET) $(CLI)", null));
    ev.layers = ctx[lib];
    try testing.expectEqualStrings("-O2 -g -fpic own []", try ev.expand("$(CFLAGS) $(MODE) [$(SECRET)]", null));
    ev.layers = &.{};
    try testing.expectEqualStrings("-O2", try ev.expand("$(CFLAGS)", null));
}
