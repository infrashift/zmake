//! Executor. It decides which targets are out of date, expands their recipes
//! (deferred phase) and runs each recipe line in its own `/bin/sh -c`.
//!
//! The scheduler runs on the main thread and owns all node state. A job runs
//! the commands of one target. With `-j`, jobs run as concurrent `Io` tasks;
//! a worker only runs commands and reports a completion under the mutex.

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const ast = @import("ast.zig");
const dag = @import("dag.zig");
const database = @import("database.zig");
const eval = @import("eval.zig");
const parser = @import("parser.zig");
const context = @import("context.zig");
const Jobserver = @import("jobserver.zig").Jobserver;
const Diagnostic = @import("diag.zig").Diagnostic;

pub const Error = error{ Exec, OutOfMemory };

pub const Options = struct {
    jobs: u32,
    dry_run: bool,
    env: *const std.process.Environ.Map,
    keep_going: bool = false,
    question: bool = false,
    touch: bool = false,
    always_make: bool = false,
    silent: bool = false,
};

/// The result of a run. `outdated`: under `-q`, a goal is not up to date.
pub const Outcome = enum { success, failed, outdated };

const NodeState = struct {
    pending: u32 = 0,
    started: bool = false,
    done: bool = false,
    /// The recipe ran, or the target is phony: dependents treat it as newer.
    rebuilt: bool = false,
    /// A recipe line ran or printed for this node.
    ran: bool = false,
    /// The modification time after the node is done; null when missing.
    mtime: ?i96 = null,
    /// Under `-k`: the recipe of this node, or of a prerequisite, failed.
    failed: bool = false,
    /// The file on disk: the directory search result, or the name after a
    /// rebuild in the working directory.
    path: []const u8 = "",
};

fn positionOrder(_: void, a: u32, b: u32) std.math.Order {
    assert(a < ast.limits.graph_nodes_max);
    assert(b < ast.limits.graph_nodes_max);
    return std.math.order(a, b);
}

const ReadyQueue = std.PriorityQueue(u32, void, positionOrder);

const Command = struct {
    text: []const u8,
    silent: bool,
    ignore_error: bool,
    /// False under `-n`, unless the line has `+` or refers to `$(MAKE)`.
    execute: bool,
    line: u32,
    /// The input file of the recipe line, for messages.
    file: []const u8,
};

const Job = struct {
    node: dag.NodeId,
    commands: []const Command,
    /// The environment of each command: the base environment plus the exports.
    env: *const std.process.Environ.Map,
    /// The modification time before the recipe ran.
    before: ?i96,
    failed: bool = false,
};

pub const Executor = struct {
    arena: std.mem.Allocator,
    io: Io,
    graph: *const dag.Graph,
    db: *const database.Database,
    ev: *eval.Evaluator,
    opts: Options,
    js: ?*Jobserver,
    diag: *Diagnostic,
    shell: []const u8,
    states: []NodeState = &.{},
    dependents: [][]dag.NodeId = &.{},
    /// The positions in `graph.order` of the nodes that can start. The
    /// smallest position starts first, so a serial build runs in the
    /// depth-first post-order of GNU Make.
    ready: ReadyQueue = .initContext({}),
    /// The position of each node in `graph.order`.
    position: []u32 = &.{},
    finished: usize = 0,
    running: u32 = 0,
    tokens: u32 = 0,
    failed: bool = false,
    group: Io.Group = .init,
    mutex: Io.Mutex = .init,
    cond: Io.Condition = .init,
    out_mutex: Io.Mutex = .init,
    completed: [ast.limits.jobs_max]*Job = undefined,
    completed_len: u32 = 0,
    /// True when a command-line variable exists or the input file changes a
    /// variable from the environment, so jobs need their own environment.
    has_exports: bool = false,
    /// The target-specific layers of each node, or empty when the input file
    /// has no target-specific variables.
    contexts: []const []const *const eval.Layer = &.{},
    /// Under `-k`: a recipe failed.
    any_failed: bool = false,
    /// Under `-q`: a target is out of date.
    outdated: bool = false,

    /// Build every goal.
    pub fn run(ex: *Executor) Error!Outcome {
        assert(ex.graph.order.len > 0);
        ex.shell = if (ex.ev.lookup("SHELL")) |v| v.value else "/bin/sh";
        ex.has_exports = ex.needsExports();
        try ex.setup();
        ex.contexts = context.build(ex.arena, ex.ev, ex.graph, ex.db) catch |err| return ex.evalError(err);
        if (ex.contexts.len > 0) ex.has_exports = true;
        var budget: usize = ex.graph.order.len * 2 + 2;
        while (ex.finished < ex.graph.order.len and budget > 0) : (budget -= 1) {
            try ex.startReady();
            if (ex.running == 0) break;
            try ex.waitCompletions();
        }
        ex.group.await(ex.io) catch return ex.fail("interrupted", .{});
        assert(ex.running == 0);
        if (ex.js) |js| js.releaseAll() catch return ex.fail("jobserver write failed", .{});
        if (ex.failed) return .failed;
        assert(ex.finished == ex.graph.order.len);
        if (ex.any_failed) return .failed;
        return if (ex.outdated) .outdated else .success;
    }

    /// True when a variable from the command line exists, or when the input
    /// file defines a name that the environment also has.
    fn needsExports(ex: *const Executor) bool {
        assert(ex.shell.len > 0);
        var it = ex.ev.vars.iterator();
        while (it.next()) |entry| {
            const v = entry.value_ptr.*;
            if (v.origin == .command_line) return true;
            if ((v.origin == .file or v.origin == .override) and ex.opts.env.contains(entry.key_ptr.*)) return true;
        }
        assert(ex.graph.order.len > 0);
        return false;
    }

    fn fail(ex: *Executor, comptime fmt: []const u8, args: anytype) Error {
        comptime assert(fmt.len > 0);
        ex.diag.set("*** " ++ fmt ++ ".  Stop.", args);
        assert(ex.diag.len > 0);
        return error.Exec;
    }

    /// Count the open prerequisites of each node and queue the leaves.
    fn setup(ex: *Executor) Error!void {
        const n = ex.graph.nodes.len;
        ex.states = try ex.arena.alloc(NodeState, n);
        @memset(ex.states, .{});
        var rev = try ex.arena.alloc(std.ArrayList(dag.NodeId), n);
        @memset(rev, .empty);
        ex.position = try ex.arena.alloc(u32, n);
        for (ex.graph.order, 0..) |id, pos| {
            const node = ex.graph.nodes[id];
            ex.position[id] = @intCast(pos);
            ex.states[id].pending = @intCast(node.deps.len);
            ex.states[id].path = node.filePath();
            for (node.deps) |dep| try rev[dep].append(ex.arena, id);
            if (node.deps.len == 0) try ex.ready.push(ex.arena, @intCast(pos));
        }
        ex.dependents = try ex.arena.alloc([]dag.NodeId, n);
        for (rev, ex.dependents) |list, *slot| slot.* = list.items;
        assert(ex.states.len == n and ex.dependents.len == n);
        assert(ex.ready.count() > 0);
    }

    fn slots(ex: *const Executor) u32 {
        assert(ex.opts.jobs >= 1);
        const n = if (ex.db.not_parallel) 1 else ex.opts.jobs;
        assert(n <= ast.limits.jobs_max);
        return n;
    }

    /// Start ready nodes while a job slot is free.
    fn startReady(ex: *Executor) Error!void {
        var budget: usize = ex.graph.order.len + 1;
        while (budget > 0 and !ex.failed and ex.ready.count() > 0) : (budget -= 1) {
            assert(ex.running <= ex.slots());
            if (ex.running > 0) {
                if (ex.running >= ex.slots()) return;
                if (ex.js) |js| {
                    if (!(js.tryAcquire() catch return ex.fail("jobserver read failed", .{}))) return;
                    ex.tokens += 1;
                }
            }
            const id = ex.graph.order[ex.ready.pop().?];
            const job = try ex.prepare(id) orelse {
                try ex.balanceTokens();
                try ex.complete(id);
                continue;
            };
            try ex.dispatch(job);
        }
        assert(ex.ready.count() <= ex.graph.order.len);
    }

    /// Keep one token for each running job after the first. The first job uses
    /// the implicit token of this process.
    fn balanceTokens(ex: *Executor) Error!void {
        const js = ex.js orelse return;
        assert(ex.tokens <= ast.limits.jobs_max);
        var budget: u32 = ast.limits.jobs_max + 1;
        while (ex.tokens > (ex.running -| 1) and budget > 0) : (budget -= 1) {
            js.release() catch return ex.fail("jobserver write failed", .{});
            ex.tokens -= 1;
        }
        assert(ex.tokens <= ex.running -| 1);
    }

    /// Run the job inline for one slot, or as a concurrent task for more.
    fn dispatch(ex: *Executor, job: *Job) Error!void {
        assert(!ex.states[job.node].done);
        assert(job.commands.len > 0);
        ex.states[job.node].started = true;
        ex.running += 1;
        if (ex.slots() == 1) {
            ex.runJob(job);
            return ex.waitCompletions();
        }
        ex.group.concurrent(ex.io, worker, .{ ex, job }) catch {
            ex.runJob(job);
        };
        assert(ex.running >= 1);
    }

    fn worker(ex: *Executor, job: *Job) void {
        assert(ex.running >= 1);
        assert(job.commands.len > 0);
        ex.runJob(job);
    }

    /// Run the commands of a job, then queue its completion. Runs on any thread.
    fn runJob(ex: *Executor, job: *Job) void {
        assert(job.commands.len > 0);
        for (job.commands) |cmd| {
            if (!cmd.silent or !cmd.execute) ex.echo(cmd.text);
            if (!cmd.execute) continue;
            if (ex.runCommand(job, cmd)) continue;
            job.failed = true;
            break;
        }
        ex.mutex.lockUncancelable(ex.io);
        defer ex.mutex.unlock(ex.io);
        assert(ex.completed_len < ex.completed.len);
        ex.completed[ex.completed_len] = job;
        ex.completed_len += 1;
        ex.cond.signal(ex.io);
    }

    /// Run one command. Return true on success or on an ignored error.
    fn runCommand(ex: *Executor, job: *const Job, cmd: Command) bool {
        assert(cmd.execute);
        const target = ex.graph.nodes[job.node].name;
        // GNU Make writes `[<builtin>: x.o]` for a built-in rule, which has no line.
        var loc_buf: [Diagnostic.capacity]u8 = undefined;
        const file = if (cmd.line > 0)
            std.fmt.bufPrint(&loc_buf, "{s}:{d}", .{ cmd.file, cmd.line }) catch cmd.file
        else
            cmd.file;
        const files: []const Io.File = if (ex.js) |js| js.files else &.{};
        var child = std.process.spawn(ex.io, .{
            .argv = &.{ ex.shell, "-c", cmd.text },
            .environ_map = job.env,
            .inherit_files = files,
        }) catch |err| {
            ex.printf("zmake: {s}: {s}\n", .{ ex.shell, @errorName(err) });
            ex.printf("zmake: *** [{s}: {s}] Error 127\n", .{ file, target });
            return false;
        };
        const term = child.wait(ex.io) catch {
            ex.printf("zmake: *** [{s}: {s}] Interrupted\n", .{ file, target });
            return false;
        };
        switch (term) {
            .exited => |code| {
                if (code == 0) return true;
                const ignored: []const u8 = if (cmd.ignore_error) " (ignored)" else "";
                const stars: []const u8 = if (cmd.ignore_error) "" else "*** ";
                ex.printf("zmake: {s}[{s}: {s}] Error {d}{s}\n", .{ stars, file, target, code, ignored });
            },
            else => ex.printf("zmake: *** [{s}: {s}] {f}\n", .{ file, target, term }),
        }
        assert(term != .exited or term.exited != 0);
        return cmd.ignore_error and term == .exited;
    }

    fn echo(ex: *Executor, text: []const u8) void {
        assert(text.len > 0);
        ex.out_mutex.lockUncancelable(ex.io);
        defer ex.out_mutex.unlock(ex.io);
        const stdout = Io.File.stdout();
        stdout.writeStreamingAll(ex.io, text) catch return;
        stdout.writeStreamingAll(ex.io, "\n") catch return;
    }

    /// Print a message to stderr under the output lock.
    fn printf(ex: *Executor, comptime fmt: []const u8, args: anytype) void {
        comptime assert(fmt.len > 0);
        var buf: [Diagnostic.capacity + 256]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
        assert(text.len > 0);
        ex.out_mutex.lockUncancelable(ex.io);
        defer ex.out_mutex.unlock(ex.io);
        Io.File.stderr().writeStreamingAll(ex.io, text) catch return;
    }

    /// Wait for at least one completion, then finish each completed job.
    fn waitCompletions(ex: *Executor) Error!void {
        assert(ex.running > 0);
        var done: [ast.limits.jobs_max]*Job = undefined;
        ex.mutex.lockUncancelable(ex.io);
        var spins: u32 = 0;
        while (ex.completed_len == 0 and spins < std.math.maxInt(u32)) : (spins += 1) {
            ex.cond.waitUncancelable(ex.io, &ex.mutex);
        }
        const n = ex.completed_len;
        @memcpy(done[0..n], ex.completed[0..n]);
        ex.completed_len = 0;
        ex.mutex.unlock(ex.io);
        for (done[0..n]) |job| try ex.finishJob(job);
        assert(n > 0);
    }

    fn finishJob(ex: *Executor, job: *Job) Error!void {
        assert(ex.running > 0);
        ex.running -= 1;
        try ex.balanceTokens();
        if (job.failed) {
            try ex.removeFailedTarget(job);
            if (ex.opts.keep_going) {
                // `-k`: the targets that need this one fail too; the others go on.
                ex.states[job.node].failed = true;
                ex.any_failed = true;
                return ex.complete(job.node);
            }
            if (!ex.failed and ex.running > 0) ex.printf("zmake: *** Waiting for unfinished jobs....\n", .{});
            ex.failed = true;
            return;
        }
        const st = &ex.states[job.node];
        st.rebuilt = true;
        st.ran = true;
        try ex.complete(job.node);
        assert(st.done);
    }

    /// Delete a file target that the failed recipe changed. Legacy mode does
    /// this only with `.DELETE_ON_ERROR`, as GNU Make does. Modern mode always does.
    fn removeFailedTarget(ex: *Executor, job: *const Job) Error!void {
        const node = ex.graph.nodes[job.node];
        assert(job.failed);
        assert(node.name.len > 0);
        if (node.kind != .file or ex.opts.dry_run or ex.db.precious.contains(node.name)) return;
        if (ex.db.mode == .legacy and !ex.db.delete_on_error) return;
        const after = try ex.mtimeOf(node.name);
        if (after == null or (job.before != null and after.? == job.before.?)) return;
        Io.Dir.cwd().deleteFile(ex.io, node.name) catch |err| {
            ex.printf("zmake: *** cannot delete '{s}': {s}\n", .{ node.name, @errorName(err) });
            return;
        };
        ex.printf("zmake: *** Deleting file '{s}'\n", .{node.name});
    }

    /// Mark a node done. Queue each dependent whose prerequisites are all done.
    fn complete(ex: *Executor, id: dag.NodeId) Error!void {
        const st = &ex.states[id];
        assert(!st.done);
        st.done = true;
        ex.finished += 1;
        if (ex.graph.nodes[id].kind == .file) st.mtime = try ex.mtimeOf(st.path);
        if (ex.graph.nodes[id].kind.isPhony()) st.rebuilt = true;
        for (ex.dependents[id]) |dep| {
            assert(ex.states[dep].pending > 0);
            ex.states[dep].pending -= 1;
            if (ex.states[dep].pending == 0) try ex.ready.push(ex.arena, ex.position[dep]);
        }
        try ex.reportGoal(id);
    }

    pub fn mtimeOf(ex: *Executor, name: []const u8) Error!?i96 {
        assert(name.len > 0);
        const st = Io.Dir.cwd().statFile(ex.io, name, .{}) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return null,
            else => return ex.fail("{s}: {s}", .{ name, @errorName(err) }),
        };
        return st.mtime.nanoseconds;
    }

    /// Decide whether node `id` runs. Return its job, or null when nothing runs.
    fn prepare(ex: *Executor, id: dag.NodeId) Error!?*Job {
        const node = ex.graph.nodes[id];
        assert(ex.states[id].pending == 0);
        assert(!ex.states[id].started and !ex.states[id].done);
        if (ex.opts.keep_going and ex.depFailed(id)) {
            ex.states[id].failed = true;
            return null;
        }
        var before = if (node.kind == .file) try ex.mtimeOf(ex.states[id].path) else null;
        if (node.kind == .inferred_phony and try ex.mtimeOf(node.name) != null) {
            ex.printf("zmake: warning: target '{s}' shadows existing path './{s}'; prefix with '@{s}:' to silence\n", .{ node.name, node.name, node.name });
        }
        if (node.instances.len > 0) return ex.prepareDoubleColon(id, before);
        const newer = try ex.newerOf(node.prerequisites, before);
        const out_of_date = ex.opts.always_make or node.kind.isPhony() or before == null or newer.len > 0;
        if (!out_of_date) return null;
        if (ex.opts.question or ex.opts.touch) return ex.skipRecipe(id);
        if (node.kind == .file and ex.states[id].path.ptr != node.name.ptr) {
            // GNU Make rebuilds a target that directory search found in the
            // working directory, under its own name.
            ex.states[id].path = node.name;
            before = try ex.mtimeOf(node.name);
        }
        if (node.recipes.len == 0) {
            ex.states[id].rebuilt = true;
            return null;
        }
        if (ex.contexts.len > 0) ex.ev.layers = ex.contexts[id];
        defer ex.ev.layers = &.{};
        const commands = try ex.expandRecipe(id, newer);
        if (commands.len == 0) {
            ex.states[id].rebuilt = true;
            return null;
        }
        const auto: eval.Auto = .{ .target = node.name, .prerequisites = try ex.pathsOf(node.prerequisites), .stem = node.stem, .newer = try ex.pathsOf(newer), .order_only = try ex.pathsOf(node.order_only) };
        const env = try ex.jobEnvironment(&auto);
        const job = try ex.arena.create(Job);
        job.* = .{ .node = id, .commands = commands, .before = before, .env = env };
        assert(job.commands.len > 0);
        return job;
    }

    /// `-q` and `-t` run no recipe for an out-of-date node. `-q` notes that a
    /// goal is not up to date. `-t` sets the time of a file target to now and
    /// prints `touch NAME`, as GNU Make does.
    fn skipRecipe(ex: *Executor, id: dag.NodeId) Error!?*Job {
        assert(ex.opts.question or ex.opts.touch);
        const node = ex.graph.nodes[id];
        ex.states[id].rebuilt = true;
        if (ex.opts.question) {
            ex.outdated = true;
            return null;
        }
        if (node.kind != .file) return null;
        if (!ex.opts.silent) ex.echo(try std.fmt.allocPrint(ex.arena, "touch {s}", .{node.name}));
        if (!ex.opts.dry_run) try ex.touchFile(node.name);
        ex.states[id].ran = true;
        assert(ex.states[id].rebuilt);
        return null;
    }

    fn touchFile(ex: *Executor, name: []const u8) Error!void {
        assert(name.len > 0);
        const dir = Io.Dir.cwd();
        if (try ex.mtimeOf(name) == null) {
            const file = dir.createFile(ex.io, name, .{ .truncate = false }) catch |e| return ex.fail("touch {s}: {s}", .{ name, @errorName(e) });
            file.close(ex.io);
            return;
        }
        dir.setTimestampsNow(ex.io, name, .{}) catch |err| return ex.fail("touch {s}: {s}", .{ name, @errorName(err) });
        assert(ex.opts.touch);
    }

    /// True when a prerequisite of node `id` failed under `-k`.
    fn depFailed(ex: *const Executor, id: dag.NodeId) bool {
        assert(ex.opts.keep_going);
        for (ex.graph.nodes[id].deps) |d| {
            if (ex.states[d].failed) return true;
        }
        assert(ex.states[id].pending == 0);
        return false;
    }

    /// The paths on disk of prerequisite names, for `$<`, `$^`, `$+` and `$?`.
    fn pathsOf(ex: *Executor, names: []const []const u8) Error![]const []const u8 {
        const paths = try ex.arena.alloc([]const u8, names.len);
        for (names, paths) |name, *slot| {
            const id = ex.graph.index.get(name).?;
            assert(ex.states[id].done);
            slot.* = ex.states[id].path;
        }
        assert(paths.len == names.len);
        return paths;
    }

    /// Each double-colon rule runs when the target is missing, when the rule
    /// has no prerequisites, or when one of its prerequisites is newer. The
    /// job runs the recipes of these rules in file order.
    fn prepareDoubleColon(ex: *Executor, id: dag.NodeId, before: ?i96) Error!?*Job {
        const node = ex.graph.nodes[id];
        assert(node.instances.len > 0 and node.recipes.len == 0);
        if (ex.contexts.len > 0) ex.ev.layers = ex.contexts[id];
        defer ex.ev.layers = &.{};
        const silent = ex.opts.silent or ex.db.silent_all or ex.db.silent.contains(node.name);
        var commands: std.ArrayList(Command) = .empty;
        var due: usize = 0;
        for (node.instances) |inst| {
            const newer = try ex.newerOf(inst.prerequisites, before);
            if (!ex.opts.always_make and !node.kind.isPhony() and before != null and newer.len == 0 and inst.prerequisites.len > 0) continue;
            due += 1;
            if (ex.opts.question or ex.opts.touch) return ex.skipRecipe(id);
            const auto: eval.Auto = .{ .target = node.name, .prerequisites = try ex.pathsOf(inst.prerequisites), .stem = inst.stem, .newer = try ex.pathsOf(newer), .order_only = try ex.pathsOf(inst.order_only) };
            try ex.appendCommands(&commands, inst.recipes, &auto, silent, inst.file);
        }
        if (due == 0) return null;
        ex.states[id].rebuilt = true;
        if (commands.items.len == 0) return null;
        const auto: eval.Auto = .{ .target = node.name, .prerequisites = try ex.pathsOf(node.prerequisites), .stem = "", .newer = &.{} };
        const job = try ex.arena.create(Job);
        job.* = .{ .node = id, .commands = commands.items, .before = before, .env = try ex.jobEnvironment(&auto) };
        assert(job.commands.len > 0);
        return job;
    }

    /// The prerequisites in `names` that make a target with `target_mtime`
    /// out of date (`$?`). A missing target makes each one newer.
    fn newerOf(ex: *Executor, names: []const []const u8, target_mtime: ?i96) Error![]const []const u8 {
        var newer: std.ArrayList([]const u8) = .empty;
        for (names) |name| {
            const dep = ex.graph.index.get(name).?;
            const ds = ex.states[dep];
            assert(ds.done);
            const is_newer = ex.opts.always_make or if (target_mtime) |t|
                ex.graph.nodes[dep].kind.isPhony() or ds.mtime == null or ds.mtime.? > t or (ex.opts.dry_run and ds.rebuilt)
            else
                true;
            if (is_newer and !containsName(newer.items, name)) try newer.append(ex.arena, name);
        }
        assert(newer.items.len <= names.len);
        assert(ex.finished <= ex.graph.order.len);
        return newer.items;
    }

    /// Expand every recipe line before the first one runs, as GNU Make does.
    fn expandRecipe(ex: *Executor, id: dag.NodeId, newer: []const []const u8) Error![]const Command {
        const node = ex.graph.nodes[id];
        assert(node.recipes.len > 0);
        assert(ex.states[id].pending == 0);
        const auto: eval.Auto = .{ .target = node.name, .prerequisites = try ex.pathsOf(node.prerequisites), .stem = node.stem, .newer = try ex.pathsOf(newer), .order_only = try ex.pathsOf(node.order_only) };
        const silent_target = ex.opts.silent or ex.db.silent_all or ex.db.silent.contains(node.name);
        var commands: std.ArrayList(Command) = .empty;
        try ex.appendCommands(&commands, node.recipes, &auto, silent_target, node.file);
        assert(commands.items.len <= ast.limits.recipe_lines_max);
        return commands.items;
    }

    /// Expand `recipes` and add one command for each line of the result. A
    /// canned recipe from `define` expands to several lines; GNU Make runs each
    /// line as its own command, with its own prefixes.
    fn appendCommands(ex: *Executor, commands: *std.ArrayList(Command), recipes: []const ast.RecipeLine, auto: *const eval.Auto, silent_target: bool, file: []const u8) Error!void {
        assert(auto.target.len > 0);
        if (file.len > 0) ex.ev.filename = file;
        for (recipes) |r| {
            ex.ev.line = r.line;
            const text = ex.ev.expand(r.text, auto) catch |err| return ex.evalError(err);
            var rest = text;
            while (nextCommand(&rest)) |piece| {
                const p = parser.recipeLine(piece, r.line);
                if (std.mem.trim(u8, p.text, " \t\n").len == 0) continue;
                if (commands.items.len >= ast.limits.recipe_lines_max) return ex.fail("more than {d} commands in one recipe", .{ast.limits.recipe_lines_max});
                const always = r.always_run or p.always_run or mentionsMake(r.text);
                try commands.append(ex.arena, .{
                    .text = p.text,
                    .silent = r.silent or p.silent or silent_target,
                    .ignore_error = r.ignore_error or p.ignore_error,
                    .execute = !ex.opts.dry_run or always,
                    .line = r.line,
                    .file = file,
                });
            }
        }
        assert(commands.items.len <= ast.limits.recipe_lines_max);
    }

    /// The base environment plus each exported variable, expanded for this
    /// target, minus each `unexport` name. See `Evaluator.exported`.
    fn jobEnvironment(ex: *Executor, auto: *const eval.Auto) Error!*const std.process.Environ.Map {
        const base = ex.opts.env;
        if (ex.ev.export_flags.count() == 0 and !ex.ev.export_all and !ex.has_exports) return base;
        const env = try ex.arena.create(std.process.Environ.Map);
        env.* = try base.clone(ex.arena);
        var it = ex.ev.vars.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const v = entry.value_ptr.*;
            if (v.origin == .environment and ex.ev.export_flags.get(name) == null) continue;
            if (!ex.ev.exported(name, v, base.contains(name))) continue;
            const value = if (v.recursive) ex.ev.expand(v.value, auto) catch |err| return ex.evalError(err) else v.value;
            try env.put(name, value);
        }
        try ex.layerExports(env, auto);
        var flags = ex.ev.export_flags.iterator();
        while (flags.next()) |f| {
            if (!f.value_ptr.* and env.contains(f.key_ptr.*)) {
                const removed = env.swapRemove(f.key_ptr.*);
                assert(removed);
            }
        }
        assert(env.count() >= 1 or base.count() == 0);
        return env;
    }

    /// Target-specific variables: a name that the global rules export, or a
    /// variable with the `export` modifier, gets the value of the target.
    fn layerExports(ex: *Executor, env: *std.process.Environ.Map, auto: *const eval.Auto) Error!void {
        assert(env.count() >= ex.opts.env.count() or ex.ev.export_flags.count() > 0);
        for (ex.ev.layers) |layer| {
            var it = layer.iterator();
            while (it.next()) |entry| {
                const name = entry.key_ptr.*;
                const v = ex.ev.lookup(name).?;
                if (!v.exported and !ex.ev.exported(name, v, ex.opts.env.contains(name))) continue;
                const value = if (v.recursive) ex.ev.expand(v.value, auto) catch |err| return ex.evalError(err) else v.value;
                try env.put(name, value);
            }
        }
        assert(ex.ev.layers.len <= ex.graph.nodes.len);
    }

    fn evalError(ex: *Executor, err: eval.Error) Error {
        assert(ex.ev.filename.len > 0);
        assert(err == error.OutOfMemory or ex.ev.diag.len > 0);
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.Eval => blk: {
                // main.zig passes one Diagnostic to both. Copy only between two
                // distinct buffers: a copy onto itself aliases.
                if (ex.diag != ex.ev.diag) ex.diag.set("{s}", .{ex.ev.diag.message()});
                break :blk error.Exec;
            },
        };
    }

    /// When a goal is done and no recipe ran for it, print "is up to date" or
    /// "Nothing to be done" at once, as GNU Make does before the next goal.
    fn reportGoal(ex: *Executor, id: dag.NodeId) Error!void {
        assert(ex.states[id].done);
        if (std.mem.indexOfScalar(dag.NodeId, ex.graph.goals, id) == null) return;
        if (ex.opts.question) return;
        if (ex.states[id].failed) {
            ex.printf("zmake: Target '{s}' not remade because of errors.\n", .{ex.graph.nodes[id].name});
            return;
        }
        if (try ex.subtreeRan(id)) return;
        const node = ex.graph.nodes[id];
        if ((node.recipes.len > 0 or node.instances.len > 0) and node.kind == .file) {
            ex.out("zmake: '{s}' is up to date.\n", .{node.name});
        } else {
            ex.out("zmake: Nothing to be done for '{s}'.\n", .{node.name});
        }
        assert(ex.graph.goals.len > 0);
    }

    fn out(ex: *Executor, comptime fmt: []const u8, args: anytype) void {
        comptime assert(fmt.len > 0);
        var buf: [Diagnostic.capacity]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
        assert(text.len > 0);
        ex.out_mutex.lockUncancelable(ex.io);
        defer ex.out_mutex.unlock(ex.io);
        Io.File.stdout().writeStreamingAll(ex.io, text) catch return;
    }

    /// True when a recipe ran for `root` or any node below it.
    fn subtreeRan(ex: *Executor, root: dag.NodeId) Error!bool {
        assert(root < ex.graph.nodes.len);
        var seen = try ex.arena.alloc(bool, ex.graph.nodes.len);
        @memset(seen, false);
        var stack: std.ArrayList(dag.NodeId) = .empty;
        try stack.append(ex.arena, root);
        var budget: usize = ex.graph.nodes.len + 1;
        while (stack.items.len > 0 and budget > 0) : (budget -= 1) {
            const id = stack.items[stack.items.len - 1];
            stack.items.len -= 1;
            if (seen[id]) continue;
            seen[id] = true;
            if (ex.states[id].ran) return true;
            for (ex.graph.nodes[id].deps) |d| try stack.append(ex.arena, d);
        }
        assert(stack.items.len == 0 or budget == 0);
        return false;
    }
};

/// Cut the next command from `rest`: the text up to a newline that no backslash
/// escapes. A backslash-newline stays in the command for the shell.
fn nextCommand(rest: *[]const u8) ?[]const u8 {
    const s = rest.*;
    if (s.len == 0) return null;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\n' and (i == 0 or s[i - 1] != '\\')) break;
    }
    rest.* = if (i < s.len) s[i + 1 ..] else s[s.len..];
    assert(rest.len < s.len);
    assert(i <= s.len);
    return s[0..i];
}

test "next command splits at unescaped newlines" {
    var rest: []const u8 = "@echo one\n-false\necho a \\\n  b";
    try std.testing.expectEqualStrings("@echo one", nextCommand(&rest).?);
    try std.testing.expectEqualStrings("-false", nextCommand(&rest).?);
    try std.testing.expectEqualStrings("echo a \\\n  b", nextCommand(&rest).?);
    try std.testing.expect(nextCommand(&rest) == null);
}

fn containsName(names: []const []const u8, name: []const u8) bool {
    assert(name.len > 0);
    for (names) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
}

/// GNU Make runs a line that refers to `$(MAKE)` also under `-n`.
fn mentionsMake(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "$(MAKE)") != null or std.mem.indexOf(u8, text, "${MAKE}") != null;
}

test "mentions make" {
    try std.testing.expect(mentionsMake("+$(MAKE) -C sub"));
    try std.testing.expect(mentionsMake("${MAKE} all"));
    try std.testing.expect(!mentionsMake("make all"));
}

test "contains name" {
    const names = [_][]const u8{ "a.o", "b.o" };
    try std.testing.expect(containsName(&names, "b.o"));
    try std.testing.expect(!containsName(&names, "c.o"));
}
