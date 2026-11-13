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

/// The flags that pass to a sub-make as letters in the first word of
/// `MAKEFLAGS`, as in GNU Make.
pub const Flags = struct {
    /// `-B`: treat every target as out of date.
    always_make: bool = false,
    /// `-k`: after a failure, go on with the targets that do not need the failed one.
    keep_going: bool = false,
    /// `-n`: print the recipe lines, do not run them.
    dry_run: bool = false,
    /// `-q`: run nothing; the exit code tells whether the goals are up to date.
    question: bool = false,
    /// `-r`: no built-in implicit rules.
    no_builtin_rules: bool = false,
    /// `-R`: no built-in variables. It implies `-r`.
    no_builtin_variables: bool = false,
    /// `-s`: do not echo the recipe lines.
    silent: bool = false,
    /// `-t`: touch the out-of-date file targets instead of running their recipes.
    touch: bool = false,

    /// The letters in the order of GNU Make, which writes them in this order.
    const table = [_]struct { u8, []const u8 }{
        .{ 'B', "always_make" }, .{ 'k', "keep_going" },       .{ 'n', "dry_run" },
        .{ 'q', "question" },    .{ 'r', "no_builtin_rules" }, .{ 'R', "no_builtin_variables" },
        .{ 's', "silent" },      .{ 't', "touch" },
    };

    /// Set the flag of one letter. Return false for an unknown letter.
    pub fn setLetter(f: *Flags, c: u8) bool {
        inline for (table) |entry| {
            if (entry[0] == c) {
                @field(f, entry[1]) = true;
                if (c == 'R') f.no_builtin_rules = true;
                return true;
            }
        }
        assert(std.mem.indexOfScalar(u8, "BknqrRst", c) == null);
        return false;
    }

    /// Read the letters of a `MAKEFLAGS` word such as `nrR`.
    pub fn fromLetters(word: []const u8) Flags {
        var f: Flags = .{};
        inline for (table) |entry| {
            if (std.mem.indexOfScalar(u8, word, entry[0]) != null) @field(f, entry[1]) = true;
        }
        if (f.no_builtin_variables) f.no_builtin_rules = true;
        assert(!f.no_builtin_variables or f.no_builtin_rules);
        return f;
    }

    /// Write the letters of the set flags into `buf`. Return the used part.
    /// `buf` needs room for every letter.
    pub fn letters(f: Flags, buf: []u8) []const u8 {
        assert(buf.len >= table.len);
        var n: usize = 0;
        inline for (table) |entry| {
            if (@field(f, entry[1])) {
                buf[n] = entry[0];
                n += 1;
            }
        }
        assert(n <= table.len);
        return buf[0..n];
    }

    /// Each flag that `a` or `b` sets.
    pub fn merge(a: Flags, b: Flags) Flags {
        var f: Flags = .{};
        inline for (table) |entry| @field(f, entry[1]) = @field(a, entry[1]) or @field(b, entry[1]);
        assert(!a.dry_run or f.dry_run);
        assert(!b.dry_run or f.dry_run);
        return f;
    }
};

pub const Options = struct {
    file: ?[]const u8 = null,
    directory: ?[]const u8 = null,
    jobs: u32 = 1,
    /// True when the command line gives `-j`.
    jobs_given: bool = false,
    flags: Flags = .{},
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
    \\  -r            Do not use the built-in implicit rules.
    \\  -R            Do not define the built-in variables. Implies -r.
    \\  -k            Keep going: build the other targets after a failure.
    \\  -q            Run nothing. Exit 0 when the goals are up to date, else 1.
    \\  -t            Touch the out-of-date targets. Do not run their recipes.
    \\  -B            Treat every target as out of date.
    \\  -s            Do not echo the recipe lines.
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
    if (arg[1] != '-') return parseShort(opts, rest, diag);
    const long_flags = [_]struct { []const u8, u8 }{
        .{ "--dry-run", 'n' },              .{ "--just-print", 'n' },  .{ "--no-builtin-rules", 'r' },
        .{ "--no-builtin-variables", 'R' }, .{ "--keep-going", 'k' },  .{ "--question", 'q' },
        .{ "--touch", 't' },                .{ "--always-make", 'B' }, .{ "--silent", 's' },
        .{ "--quiet", 's' },
    };
    for (long_flags) |lf| {
        if (std.mem.eql(u8, arg, lf[0])) {
            const known = opts.flags.setLetter(lf[1]);
            assert(known);
            return 1;
        }
    }
    if (std.mem.eql(u8, arg, "--help")) {
        opts.help = true;
    } else if (std.mem.eql(u8, arg, "--modern")) {
        opts.mode = .modern;
    } else if (std.mem.eql(u8, arg, "--legacy")) {
        opts.mode = .legacy;
    } else if (longOption(arg, "--file")) |inline_value| {
        const v = try optionValue(rest, inline_value, diag);
        opts.file = v.value;
        return v.used;
    } else if (longOption(arg, "--directory")) |inline_value| {
        const v = try optionValue(rest, inline_value, diag);
        opts.directory = v.value;
        return v.used;
    } else if (longOption(arg, "--jobs")) |inline_value| {
        return parseJobs(opts, rest, inline_value, diag);
    } else {
        return usageError(diag, "unknown option '{s}'", .{arg});
    }
    assert(opts.jobs >= 1);
    return 1;
}

/// A short option or a cluster such as `-kj4` or `-sB`. A letter that takes a
/// value (`f`, `C`, `j`) takes the rest of the word, or the next argument.
fn parseShort(opts: *Options, rest: []const []const u8, diag: *Diagnostic) ParseError!usize {
    const arg = rest[0];
    assert(arg.len >= 2 and arg[0] == '-' and arg[1] != '-');
    var i: usize = 1;
    while (i < arg.len) : (i += 1) {
        const c = arg[i];
        const tail = arg[i + 1 ..];
        switch (c) {
            'h' => opts.help = true,
            'f', 'C' => {
                const v = try optionValue(rest, if (tail.len > 0) tail else null, diag);
                if (c == 'f') opts.file = v.value else opts.directory = v.value;
                return v.used;
            },
            'j' => return parseJobs(opts, rest, if (tail.len > 0) tail else null, diag),
            else => if (!opts.flags.setLetter(c)) return usageError(diag, "unknown option '-{c}'", .{c}),
        }
    }
    assert(i == arg.len);
    return 1;
}

/// `-j` without a number means "no limit" in GNU Make. zmake uses `limits.jobs_max`.
fn parseJobs(opts: *Options, rest: []const []const u8, inline_value: ?[]const u8, diag: *Diagnostic) ParseError!usize {
    assert(rest.len >= 1);
    opts.jobs_given = true;
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

/// Match `--long=VALUE` and `--long`. Return the inline value, or an
/// empty-optional (null payload) when the value is the next argument.
fn longOption(arg: []const u8, long: []const u8) ??[]const u8 {
    assert(long.len > 2 and long[0] == '-' and long[1] == '-');
    if (std.mem.eql(u8, arg, long)) return @as(?[]const u8, null);
    if (std.mem.startsWith(u8, arg, long) and arg.len > long.len and arg[long.len] == '=') {
        return @as(?[]const u8, arg[long.len + 1 ..]);
    }
    assert(arg.len >= 2);
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
    try testing.expect(o.flags.dry_run);
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

test "short option clusters and the MAKEFLAGS letters" {
    const o = try parseTest(&.{ "-kj4", "-sBf", "build.mk", "--question", "-C", "sub", "--touch", "all" });
    try testing.expect(o.flags.keep_going and o.flags.silent and o.flags.always_make);
    try testing.expect(o.flags.question and o.flags.touch);
    try testing.expectEqual(@as(u32, 4), o.jobs);
    try testing.expectEqualStrings("build.mk", o.file.?);
    try testing.expectEqualStrings("sub", o.directory.?);
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings("Bkqst", o.flags.letters(&buf));
    const back = Flags.fromLetters("Bks");
    try testing.expect(back.always_make and back.keep_going and back.silent and !back.question);
    var diag: Diagnostic = .{};
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const with_goal = try parseArgs(arena.allocator(), &.{ "--touch", "-C", "sub", "all" }, &diag);
    try testing.expectEqualStrings("all", with_goal.goals[0]);
    try testing.expectError(error.Usage, parseArgs(arena.allocator(), &.{"-kx"}, &diag));
    try testing.expectEqualStrings("unknown option '-x'", diag.message());
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
