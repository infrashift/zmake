//! zmake entry point. It parses the arguments, finds the input file and reports
//! errors. The library modules do the work.

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const zmake = @import("zmake");

pub fn main(init: std.process.Init) void {
    const code = run(init);
    assert(code == 0 or code == 2);
    std.process.exit(code);
}

/// The error message is already on stderr. The exit code is 2.
const Reported = error{Reported};

fn run(init: std.process.Init) u8 {
    const code: u8 = if (runChecked(init)) 0 else |err| switch (err) {
        error.Reported => 2,
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
    const opts = zmake.cli.parseArgs(arena, argv[1..], &diag) catch |err| switch (err) {
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
    const mk = try load(arena, io, opts, &diag);
    assert(mk.filename.len > 0);
    var ev = zmake.eval.Evaluator.init(arena, io, Io.Dir.cwd(), &diag);
    const db = try evaluate(&ev, init, opts, mk);
    assert(db.rules.len <= mk.statements.len * zmake.ast.limits.names_per_line_max);
    const graph = zmake.dag.build(arena, io, Io.Dir.cwd(), &db, opts.goals, &diag) catch |err| switch (err) {
        error.Graph => return report(io, diag.message()),
        error.OutOfMemory => return report(io, "out of memory"),
    };
    for (graph.warnings) |w| warn(io, w);
    assert(graph.goals.len >= 1);
}

fn warn(io: Io, message: []const u8) void {
    assert(message.len > 0);
    writeAll(io, Io.File.stderr(), message);
    writeAll(io, Io.File.stderr(), "\n");
}

/// Define the variables in origin order, then replay the input file.
fn evaluate(ev: *zmake.eval.Evaluator, init: std.process.Init, opts: zmake.cli.Options, mk: zmake.ast.Makefile) Reported!zmake.database.Database {
    const io = init.io;
    const make_path = std.process.executablePathAlloc(io, init.arena.allocator()) catch return report(io, "cannot find the zmake executable path");
    assert(make_path.len > 0);
    ev.defineDefaults(make_path) catch return report(io, "out of memory");
    ev.importEnvironment(init.environ_map) catch return report(io, "out of memory");
    for (opts.overrides) |o| {
        const value = if (o.simple) ev.expand(o.value, null) catch |err| return evalError(io, ev, err) else o.value;
        ev.define(o.name, value, !o.simple, .command_line) catch return report(io, "out of memory");
    }
    const db = zmake.database.load(ev, mk) catch |err| return evalError(io, ev, err);
    assert(db.mode == mk.mode);
    return db;
}

fn evalError(io: Io, ev: *zmake.eval.Evaluator, err: zmake.eval.Error) Reported {
    assert(ev.diag.len > 0 or err == error.OutOfMemory);
    return switch (err) {
        error.Eval => report(io, ev.diag.message()),
        error.OutOfMemory => report(io, "out of memory"),
    };
}

/// Find, read and parse the input file.
fn load(arena: std.mem.Allocator, io: Io, opts: zmake.cli.Options, diag: *zmake.Diagnostic) Reported!zmake.ast.Makefile {
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
    const mk = zmake.parser.parse(arena, source, input.path, input.mode, diag) catch |err| switch (err) {
        error.Syntax => return report(io, diag.message()),
        error.OutOfMemory => return report(io, "out of memory"),
    };
    assert(mk.mode == input.mode);
    return mk;
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
