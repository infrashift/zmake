//! Command-line parsing and input file discovery. See the CLI contract spec.

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const ast = @import("ast.zig");
const Diagnostic = @import("diag.zig").Diagnostic;

pub const Override = struct {
    name: []const u8,
    value: []const u8,
    /// True for `NAME:=value`: a simple variable.
    simple: bool,
};

pub const Options = struct {
    file: ?[]const u8 = null,
    directory: ?[]const u8 = null,
    jobs: u32 = 1,
    dry_run: bool = false,
    mode: ?ast.SyntaxMode = null,
    help: bool = false,
    overrides: []const Override = &.{},
    goals: []const []const u8 = &.{},
};

pub const ParseError = error{ Usage, OutOfMemory };

pub const usage =
    \\Usage: zmake [options] [VAR=value ...] [target ...]
    \\
    \\Options:
    \\  -f FILE       Read FILE as the input file.
    \\  -C DIR        Change to DIR before reading the input file.
    \\  -j N          Run up to N jobs at the same time.
    \\  -n            Print the recipe lines. Do not run them.
    \\  --modern      Use modern mode (ZMakefile syntax) for any input file.
    \\  --legacy      Use legacy mode (strict Make syntax) for any input file.
    \\  -h, --help    Print this help.
    \\
;

/// Parse the arguments after argv[0].
pub fn parseArgs(arena: std.mem.Allocator, args: []const []const u8, diag: *Diagnostic) ParseError!Options {
    var opts: Options = .{};
    var overrides: std.ArrayList(Override) = .empty;
    var goals: std.ArrayList([]const u8) = .empty;
    var only_operands = false;
    var i: usize = 0;
    while (i < args.len) {
        assert(goals.items.len + overrides.items.len <= i);
        const arg = args[i];
        if (!only_operands and std.mem.eql(u8, arg, "--")) {
            only_operands = true;
            i += 1;
        } else if (!only_operands and arg.len > 1 and arg[0] == '-') {
            const used = try parseOption(&opts, args[i..], diag);
            assert(used >= 1 and used <= 2);
            i += used;
        } else if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
            try overrides.append(arena, try parseOverride(arg, eq, diag));
            i += 1;
        } else {
            if (arg.len == 0) return usageError(diag, "empty target name", .{});
            try goals.append(arena, arg);
            i += 1;
        }
    }
    assert(i == args.len);
    opts.overrides = overrides.items;
    opts.goals = goals.items;
    assert(opts.jobs >= 1 and opts.jobs <= ast.limits.jobs_max);
    return opts;
}

fn parseOverride(arg: []const u8, eq: usize, diag: *Diagnostic) ParseError!Override {
    assert(eq < arg.len and arg[eq] == '=');
    var name = std.mem.trim(u8, arg[0..eq], " \t");
    var simple = false;
    if (std.mem.endsWith(u8, name, "::")) {
        name = name[0 .. name.len - 2];
        simple = true;
    } else if (std.mem.endsWith(u8, name, ":")) {
        name = name[0 .. name.len - 1];
        simple = true;
    }
    if (name.len == 0) return usageError(diag, "invalid variable assignment '{s}'", .{arg});
    assert(std.mem.indexOfScalar(u8, name, '=') == null);
    return .{ .name = name, .value = arg[eq + 1 ..], .simple = simple };
}

/// Parse the option at `rest[0]`. Return the number of arguments it consumes.
fn parseOption(opts: *Options, rest: []const []const u8, diag: *Diagnostic) ParseError!usize {
    assert(rest.len >= 1);
    const arg = rest[0];
    assert(arg.len > 1 and arg[0] == '-');
    if (eqlAny(arg, &.{ "-h", "--help" })) {
        opts.help = true;
    } else if (eqlAny(arg, &.{ "-n", "--dry-run", "--just-print" })) {
        opts.dry_run = true;
    } else if (std.mem.eql(u8, arg, "--modern")) {
        opts.mode = .modern;
    } else if (std.mem.eql(u8, arg, "--legacy")) {
        opts.mode = .legacy;
    } else if (valueOption(arg, "-f", "--file")) |inline_value| {
        const v = try optionValue(rest, inline_value, diag);
        opts.file = v.value;
        return v.used;
    } else if (valueOption(arg, "-C", "--directory")) |inline_value| {
        const v = try optionValue(rest, inline_value, diag);
        opts.directory = v.value;
        return v.used;
    } else if (valueOption(arg, "-j", "--jobs")) |inline_value| {
        return parseJobs(opts, rest, inline_value, diag);
    } else {
        return usageError(diag, "unknown option '{s}'", .{arg});
    }
    assert(opts.jobs >= 1);
    return 1;
}

/// `-j` without a number means "no limit" in GNU Make. zmake uses `limits.jobs_max`.
fn parseJobs(opts: *Options, rest: []const []const u8, inline_value: ?[]const u8, diag: *Diagnostic) ParseError!usize {
    assert(rest.len >= 1);
    var text: ?[]const u8 = inline_value;
    var used: usize = 1;
    if (text == null and rest.len > 1) {
        // A non-number after `-j` is a target, not a job count.
        if (std.fmt.parseInt(u32, rest[1], 10)) |_| {
            text = rest[1];
            used = 2;
        } else |err| switch (err) {
            error.Overflow, error.InvalidCharacter => {},
        }
    }
    const t = text orelse {
        opts.jobs = ast.limits.jobs_max;
        return used;
    };
    const n = std.fmt.parseInt(u32, t, 10) catch return usageError(diag, "invalid job count '{s}'", .{t});
    if (n == 0) return usageError(diag, "job count must be 1 or more", .{});
    opts.jobs = @min(n, ast.limits.jobs_max);
    assert(opts.jobs >= 1 and opts.jobs <= ast.limits.jobs_max);
    assert(used == 1 or used == 2);
    return used;
}

const OptionValue = struct { value: []const u8, used: usize };

fn optionValue(rest: []const []const u8, inline_value: ?[]const u8, diag: *Diagnostic) ParseError!OptionValue {
    assert(rest.len >= 1);
    if (inline_value) |v| {
        if (v.len == 0) return usageError(diag, "option '{s}' requires a value", .{rest[0]});
        assert(v.ptr != rest[0].ptr);
        return .{ .value = v, .used = 1 };
    }
    if (rest.len < 2) return usageError(diag, "option '{s}' requires an argument", .{rest[0]});
    assert(rest[0][0] == '-');
    return .{ .value = rest[1], .used = 2 };
}

/// Match `-xVALUE`, `-x`, `--long=VALUE` and `--long`. Return the inline value, or
/// an empty-optional (null payload) when the value is the next argument.
fn valueOption(arg: []const u8, short: []const u8, long: []const u8) ??[]const u8 {
    assert(short.len == 2 and short[0] == '-');
    assert(long.len > 2 and long[0] == '-' and long[1] == '-');
    if (std.mem.eql(u8, arg, short) or std.mem.eql(u8, arg, long)) return @as(?[]const u8, null);
    if (std.mem.startsWith(u8, arg, long) and arg.len > long.len and arg[long.len] == '=') {
        return @as(?[]const u8, arg[long.len + 1 ..]);
    }
    if (std.mem.startsWith(u8, arg, short) and !std.mem.startsWith(u8, arg, "--")) {
        return @as(?[]const u8, arg[short.len..]);
    }
    return null;
}

fn eqlAny(arg: []const u8, names: []const []const u8) bool {
    assert(names.len > 0);
    assert(arg.len > 0);
    for (names) |n| {
        if (std.mem.eql(u8, arg, n)) return true;
    }
    return false;
}

fn usageError(diag: *Diagnostic, comptime fmt: []const u8, args: anytype) ParseError {
    comptime assert(fmt.len > 0);
    diag.set(fmt, args);
    assert(diag.len > 0);
    return error.Usage;
}

pub const InputFile = struct {
    path: []const u8,
    mode: ast.SyntaxMode,
};

const Candidate = struct { name: []const u8, mode: ast.SyntaxMode };

/// The discovery order: modern names first, then the GNU Make order.
pub const candidates = [_]Candidate{
    .{ .name = "ZMakefile", .mode = .modern },
    .{ .name = "Make.zig.mk", .mode = .modern },
    .{ .name = "GNUmakefile", .mode = .legacy },
    .{ .name = "makefile", .mode = .legacy },
    .{ .name = "Makefile", .mode = .legacy },
};

/// The basename `ZMakefile` or `Make.zig.mk` selects modern mode.
pub fn modeForPath(path: []const u8) ast.SyntaxMode {
    assert(path.len > 0);
    const base = std.fs.path.basename(path);
    assert(base.len <= path.len);
    for (candidates) |c| {
        if (std.mem.eql(u8, base, c.name)) return c.mode;
    }
    return .legacy;
}

pub const DiscoverError = error{NoInputFile} || Io.Dir.AccessError;

/// Select the input file and its syntax mode.
pub fn discover(io: Io, dir: Io.Dir, opts: Options, diag: *Diagnostic) DiscoverError!InputFile {
    if (opts.file) |path| {
        assert(path.len > 0);
        return .{ .path = path, .mode = opts.mode orelse modeForPath(path) };
    }
    for (candidates) |c| {
        assert(c.name.len > 0);
        if (dir.access(io, c.name, .{})) |_| {
            return .{ .path = c.name, .mode = opts.mode orelse c.mode };
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => |e| return e,
        }
    }
    diag.set("*** No targets specified and no makefile found.  Stop.", .{});
    assert(diag.len > 0);
    return error.NoInputFile;
}

const testing = std.testing;

fn parseTest(args: []const []const u8) !Options {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    var opts = try parseArgs(arena.allocator(), args, &diag);
    // The arena owns these slices. Drop them before the arena goes away.
    opts.overrides = &.{};
    opts.goals = &.{};
    return opts;
}

test "parse options" {
    const o = try parseTest(&.{ "-f", "x.mk", "-C", "dir", "-j4", "-n", "--modern" });
    try testing.expectEqualStrings("x.mk", o.file.?);
    try testing.expectEqualStrings("dir", o.directory.?);
    try testing.expectEqual(@as(u32, 4), o.jobs);
    try testing.expect(o.dry_run);
    try testing.expectEqual(ast.SyntaxMode.modern, o.mode.?);
}

test "parse inline and long option values" {
    const o = try parseTest(&.{ "-fZMakefile", "--directory=sub", "--jobs=2", "--legacy" });
    try testing.expectEqualStrings("ZMakefile", o.file.?);
    try testing.expectEqualStrings("sub", o.directory.?);
    try testing.expectEqual(@as(u32, 2), o.jobs);
    try testing.expectEqual(ast.SyntaxMode.legacy, o.mode.?);
}

test "parse -j without a number and -j with a separate number" {
    try testing.expectEqual(ast.limits.jobs_max, (try parseTest(&.{ "-j", "all" })).jobs);
    try testing.expectEqual(@as(u32, 8), (try parseTest(&.{ "-j", "8" })).jobs);
}

test "parse overrides and goals" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const o = try parseArgs(arena.allocator(), &.{ "CC=clang", "X:=1", "all", "--", "-weird" }, &diag);
    try testing.expectEqual(@as(usize, 2), o.overrides.len);
    try testing.expectEqualStrings("CC", o.overrides[0].name);
    try testing.expectEqualStrings("clang", o.overrides[0].value);
    try testing.expect(!o.overrides[0].simple);
    try testing.expectEqualStrings("X", o.overrides[1].name);
    try testing.expect(o.overrides[1].simple);
    try testing.expectEqual(@as(usize, 2), o.goals.len);
    try testing.expectEqualStrings("-weird", o.goals[1]);
}

test "parse errors" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    try testing.expectError(error.Usage, parseArgs(arena.allocator(), &.{"-x"}, &diag));
    try testing.expectError(error.Usage, parseArgs(arena.allocator(), &.{"-f"}, &diag));
    try testing.expectError(error.Usage, parseArgs(arena.allocator(), &.{"-j0"}, &diag));
    try testing.expectError(error.Usage, parseArgs(arena.allocator(), &.{"=x"}, &diag));
    try testing.expectEqualStrings("invalid variable assignment '=x'", diag.message());
}

test "mode for path" {
    try testing.expectEqual(ast.SyntaxMode.modern, modeForPath("a/b/ZMakefile"));
    try testing.expectEqual(ast.SyntaxMode.modern, modeForPath("Make.zig.mk"));
    try testing.expectEqual(ast.SyntaxMode.legacy, modeForPath("Makefile"));
    try testing.expectEqual(ast.SyntaxMode.legacy, modeForPath("build.mk"));
}

test "discover prefers ZMakefile over Makefile" {
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var diag: Diagnostic = .{};
    try testing.expectError(error.NoInputFile, discover(io, tmp.dir, .{}, &diag));
    try tmp.dir.writeFile(io, .{ .sub_path = "Makefile", .data = "" });
    const legacy = try discover(io, tmp.dir, .{}, &diag);
    try testing.expectEqualStrings("Makefile", legacy.path);
    try testing.expectEqual(ast.SyntaxMode.legacy, legacy.mode);
    try tmp.dir.writeFile(io, .{ .sub_path = "ZMakefile", .data = "" });
    const modern = try discover(io, tmp.dir, .{}, &diag);
    try testing.expectEqualStrings("ZMakefile", modern.path);
    try testing.expectEqual(ast.SyntaxMode.modern, modern.mode);
    const forced = try discover(io, tmp.dir, .{ .mode = .legacy }, &diag);
    try testing.expectEqual(ast.SyntaxMode.legacy, forced.mode);
}

test "discover honors -f and its basename" {
    var diag: Diagnostic = .{};
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try discover(testing.io, tmp.dir, .{ .file = "sub/ZMakefile" }, &diag);
    try testing.expectEqual(ast.SyntaxMode.modern, f.mode);
}
