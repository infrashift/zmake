//! zmake entry point. It parses the arguments, finds the input file and reports
//! errors. The library modules do the work.

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const zmake = @import("zmake");

pub fn main(init: std.process.Init) void {
    const code = run(init);
    assert(code <= 2);
    std.process.exit(code);
}

/// `Reported`: the error message is already on stderr; the exit code is 2.
/// `Outdated`: under `-q`, a goal is not up to date; the exit code is 1.
const Reported = error{ Reported, Outdated };

fn run(init: std.process.Init) u8 {
    const code: u8 = if (runChecked(init)) 0 else |err| switch (err) {
        error.Reported => 2,
        error.Outdated => 1,
    };
    assert(code <= 2);
    return code;
}

fn runChecked(init: std.process.Init) Reported!void {
    const arena = init.arena.allocator();
    const io = init.io;
    var diag: zmake.Diagnostic = .{};
    const argv = init.minimal.args.toSlice(arena) catch return report(io, "out of memory");
    assert(argv.len >= 1);
    var opts = zmake.cli.parseArgs(arena, argv[1..], &diag) catch |err| switch (err) {
        error.Usage => return reportUsage(io, diag.message()),
        error.OutOfMemory => return report(io, "out of memory"),
    };
    assert(opts.jobs >= 1 and opts.jobs <= zmake.ast.limits.jobs_max);
    if (opts.help) {
        writeAll(io, Io.File.stdout(), zmake.cli.usage);
        return;
    }
    if (opts.directory) |dir| {
        std.process.setCurrentPath(io, dir) catch |err| {
            diag.set("*** {s}: {s}.  Stop.", .{ dir, @errorName(err) });
            return report(io, diag.message());
        };
    }
    const mf = zmake.jobserver.parseMakeflags(arena, init.environ_map.get("MAKEFLAGS") orelse "") catch return report(io, "out of memory");
    opts.flags = opts.flags.merge(mf.flags);
    const input = try load(arena, io, opts, &diag);
    assert(input.path.len > 0);
    var ev = zmake.eval.Evaluator.init(arena, io, Io.Dir.cwd(), &diag);
    const db = try evaluate(&ev, init, opts, mf, input);
    assert(db.mode == input.mode);
    const graph = zmake.dag.build(arena, io, Io.Dir.cwd(), &db, opts.goals, &diag) catch |err| switch (err) {
        error.Graph => return report(io, diag.message()),
        error.OutOfMemory => return report(io, "out of memory"),
    };
    for (graph.warnings) |w| warn(io, w);
    assert(graph.goals.len >= 1);
    try execute(init, opts, mf, &ev, &db, &graph, &diag);
}

/// Set up the jobserver and the child environment, then run the executor.
fn execute(
    init: std.process.Init,
    opts: zmake.cli.Options,
    mf: zmake.jobserver.Makeflags,
    ev: *zmake.eval.Evaluator,
    db: *const zmake.database.Database,
    graph: *const zmake.dag.Graph,
    diag: *zmake.Diagnostic,
) Reported!void {
    const io = init.io;
    const arena = init.arena.allocator();
    assert(graph.order.len > 0);
    var jobs = opts.jobs;
    const js = try setupJobserver(init, opts, mf, &jobs);
    assert(jobs >= 1);
    const overrides = std.mem.concat(arena, zmake.cli.Override, &.{ mf.overrides, opts.overrides }) catch return report(io, "out of memory");
    const env = childEnvironment(init, opts.flags, jobs, js, overrides) catch return report(io, "out of memory");
    var ex: zmake.executor.Executor = .{
        .arena = arena,
        .io = io,
        .graph = graph,
        .db = db,
        .ev = ev,
        .opts = .{
            .jobs = jobs,
            .dry_run = opts.flags.dry_run,
            .env = env,
            .keep_going = opts.flags.keep_going,
            .question = opts.flags.question,
            .touch = opts.flags.touch,
            .always_make = opts.flags.always_make,
            .silent = opts.flags.silent,
        },
        .js = js,
        .diag = diag,
        .shell = "/bin/sh",
    };
    const outcome = ex.run() catch |err| switch (err) {
        error.Exec => return report(io, diag.message()),
        error.OutOfMemory => return report(io, "out of memory"),
    };
    switch (outcome) {
        .success => {},
        .failed => return error.Reported,
        .outdated => return error.Outdated,
    }
}

/// `-jN` with N > 1 creates a pool. Without `-j`, zmake joins the pool of a parent make.
fn setupJobserver(init: std.process.Init, opts: zmake.cli.Options, mf: zmake.jobserver.Makeflags, jobs: *u32) Reported!?*zmake.jobserver.Jobserver {
    const io = init.io;
    const arena = init.arena.allocator();
    assert(opts.jobs >= 1 and jobs.* == opts.jobs);
    const js = arena.create(zmake.jobserver.Jobserver) catch return report(io, "out of memory");
    if (opts.jobs_given) {
        if (opts.jobs <= 1) return null;
        js.* = zmake.jobserver.Jobserver.initServer(arena, opts.jobs) catch return report(io, "cannot create the jobserver pipe");
        return js;
    }
    const auth = mf.auth orelse return null;
    const client = zmake.jobserver.Jobserver.initClient(arena, auth) catch return report(io, "invalid jobserver in MAKEFLAGS");
    js.* = client orelse {
        warn(io, "zmake: warning: jobserver unavailable: using -j1.  Add '+' to parent make rule.");
        return null;
    };
    jobs.* = @min(mf.jobs orelse zmake.ast.limits.jobs_max, zmake.ast.limits.jobs_max);
    assert(jobs.* >= 1);
    return js;
}

/// The environment of each recipe line: the zmake environment plus
/// `MAKEFLAGS` and `MAKELEVEL`.
fn childEnvironment(init: std.process.Init, flags: zmake.cli.Flags, jobs: u32, js: ?*zmake.jobserver.Jobserver, overrides: []const zmake.cli.Override) error{ OutOfMemory, Jobserver }!*std.process.Environ.Map {
    assert(jobs >= 1);
    const arena = init.arena.allocator();
    const env = try arena.create(std.process.Environ.Map);
    env.* = try init.environ_map.clone(arena);
    const auth: ?[]const u8 = if (js) |j| j.auth else null;
    const text = try zmake.jobserver.composeMakeflags(arena, flags, jobs, auth, overrides);
    if (text.len > 0) {
        try env.put("MAKEFLAGS", text);
    } else if (env.contains("MAKEFLAGS")) {
        const removed = env.swapRemove("MAKEFLAGS");
        assert(removed);
    }
    const level = std.fmt.parseInt(u32, init.environ_map.get("MAKELEVEL") orelse "0", 10) catch 0;
    try env.put("MAKELEVEL", try std.fmt.allocPrint(arena, "{d}", .{level + 1}));
    assert(env.contains("MAKELEVEL"));
    return env;
}

fn warn(io: Io, message: []const u8) void {
    assert(message.len > 0);
    writeAll(io, Io.File.stderr(), message);
    writeAll(io, Io.File.stderr(), "\n");
}

/// Define the variables in origin order, then read the input file.
fn evaluate(ev: *zmake.eval.Evaluator, init: std.process.Init, opts: zmake.cli.Options, mf: zmake.jobserver.Makeflags, input: Input) Reported!zmake.database.Database {
    const io = init.io;
    const make_path = std.process.executablePathAlloc(io, init.arena.allocator()) catch return report(io, "cannot find the zmake executable path");
    assert(make_path.len > 0);
    ev.defineDefaults(make_path) catch return report(io, "out of memory");
    if (!opts.flags.no_builtin_variables) ev.defineBuiltins() catch return report(io, "out of memory");
    ev.builtin_rules = !opts.flags.no_builtin_rules;
    ev.importEnvironment(init.environ_map) catch return report(io, "out of memory");
    for ([_][]const zmake.cli.Override{ mf.overrides, opts.overrides }) |list| for (list) |o| {
        const value = if (o.simple) ev.expand(o.value, null) catch |err| return evalError(io, ev, err) else o.value;
        ev.define(o.name, value, !o.simple, .command_line) catch return report(io, "out of memory");
    };
    const db = zmake.reader.read(ev, input.source, input.path, input.mode, ev.diag) catch |err| return evalError(io, ev, err);
    assert(db.mode == input.mode);
    return db;
}

fn evalError(io: Io, ev: *zmake.eval.Evaluator, err: zmake.reader.Error) Reported {
    assert(ev.diag.len > 0 or err == error.OutOfMemory);
    return switch (err) {
        error.Eval, error.Syntax => report(io, ev.diag.message()),
        error.OutOfMemory => report(io, "out of memory"),
    };
}

/// The input file: its path, its syntax mode and its text.
const Input = struct { path: []const u8, mode: zmake.ast.SyntaxMode, source: []const u8 };

/// Find and read the input file.
fn load(arena: std.mem.Allocator, io: Io, opts: zmake.cli.Options, diag: *zmake.Diagnostic) Reported!Input {
    const input = zmake.cli.discover(io, Io.Dir.cwd(), opts, diag) catch |err| switch (err) {
        error.NoInputFile => return report(io, diag.message()),
        else => |e| return report(io, @errorName(e)),
    };
    assert(input.path.len > 0);
    const limit: Io.Limit = .limited(zmake.ast.limits.input_file_bytes_max + 1);
    const source = Io.Dir.cwd().readFileAlloc(io, input.path, arena, limit) catch |err| {
        switch (err) {
            error.FileNotFound => diag.set("*** {s}: No such file or directory.  Stop.", .{input.path}),
            error.StreamTooLong => diag.set("*** {s}: larger than {d} bytes.  Stop.", .{ input.path, zmake.ast.limits.input_file_bytes_max }),
            else => diag.set("*** {s}: {s}.  Stop.", .{ input.path, @errorName(err) }),
        }
        return report(io, diag.message());
    };
    assert(source.len <= zmake.ast.limits.input_file_bytes_max + 1);
    return .{ .path = input.path, .mode = input.mode, .source = source };
}

fn report(io: Io, message: []const u8) Reported {
    assert(message.len > 0);
    const code = fail(io, message);
    assert(code == 2);
    return error.Reported;
}

fn fail(io: Io, message: []const u8) u8 {
    assert(message.len > 0);
    var buf: [zmake.Diagnostic.capacity + 16]u8 = undefined;
    // GNU Make omits the program name when the message starts with `file:line:`.
    const prefix: []const u8 = if (std.mem.indexOf(u8, message, ": *** ") != null) "" else "zmake: ";
    const line = std.fmt.bufPrint(&buf, "{s}{s}\n", .{ prefix, message }) catch return 2;
    assert(line.len == prefix.len + message.len + 1);
    writeAll(io, Io.File.stderr(), line);
    return 2;
}

fn reportUsage(io: Io, message: []const u8) Reported {
    assert(message.len > 0);
    const err = report(io, message);
    writeAll(io, Io.File.stderr(), zmake.cli.usage);
    assert(err == error.Reported);
    return err;
}

/// Write to stdout or stderr. A failed write has no other place to report to,
/// so zmake drops the text.
fn writeAll(io: Io, file: Io.File, bytes: []const u8) void {
    assert(bytes.len > 0);
    file.writeStreamingAll(io, bytes) catch return;
}
