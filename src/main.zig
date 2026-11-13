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

fn run(init: std.process.Init) u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    var diag: zmake.Diagnostic = .{};
    const argv = init.minimal.args.toSlice(arena) catch return fail(io, "out of memory");
    assert(argv.len >= 1);
    const opts = zmake.cli.parseArgs(arena, argv[1..], &diag) catch |err| switch (err) {
        error.Usage => return failUsage(io, diag.message()),
        error.OutOfMemory => return fail(io, "out of memory"),
    };
    assert(opts.jobs >= 1 and opts.jobs <= zmake.ast.limits.jobs_max);
    if (opts.help) {
        writeAll(io, Io.File.stdout(), zmake.cli.usage);
        return 0;
    }
    if (opts.directory) |dir| {
        std.process.setCurrentPath(io, dir) catch |err| {
            diag.set("*** {s}: {s}.  Stop.", .{ dir, @errorName(err) });
            return fail(io, diag.message());
        };
    }
    const input = zmake.cli.discover(io, Io.Dir.cwd(), opts, &diag) catch |err| switch (err) {
        error.NoInputFile => return fail(io, diag.message()),
        else => |e| return fail(io, @errorName(e)),
    };
    assert(input.path.len > 0);
    return 0;
}

fn fail(io: Io, message: []const u8) u8 {
    assert(message.len > 0);
    var buf: [zmake.Diagnostic.capacity + 16]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "zmake: {s}\n", .{message}) catch return 2;
    assert(line.len == message.len + "zmake: \n".len);
    writeAll(io, Io.File.stderr(), line);
    return 2;
}

fn failUsage(io: Io, message: []const u8) u8 {
    assert(message.len > 0);
    const code = fail(io, message);
    assert(code == 2);
    writeAll(io, Io.File.stderr(), zmake.cli.usage);
    return code;
}

/// Write to stdout or stderr. A failed write has no other place to report to,
/// so zmake drops the text.
fn writeAll(io: Io, file: Io.File, bytes: []const u8) void {
    assert(bytes.len > 0);
    file.writeStreamingAll(io, bytes) catch return;
}
