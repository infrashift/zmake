//! GNU Make compatible jobserver and `MAKEFLAGS` handling. See the "Jobserver
//! protocol" spec.
//!
//! zmake takes tokens through a private non-blocking descriptor. For a pipe it
//! opens `/proc/self/fd/R` again, so the pipe stays blocking for child makes,
//! which share the open file description of the original descriptor. That
//! needs Linux (ADR-0008). For a named fifo, zmake opens the path with
//! `O_NONBLOCK`, which works on each POSIX system. On macOS and the BSDs, a
//! server uses a fifo, as GNU Make 4.4 does (ADR-0020).

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const posix = std.posix;
const ast = @import("ast.zig");
const cli = @import("cli.zig");

/// `Unsupported`: this system cannot share the pipe jobserver of a parent.
pub const Error = error{ Jobserver, Unsupported, OutOfMemory };

const is_linux = builtin.os.tag == .linux;

/// The style of a new pool: a pipe on Linux, a named fifo elsewhere.
pub const default_style: cli.JobserverStyle = if (is_linux) .pipe else .fifo;

/// `mkfifo` of the C library. zmake links the C library on each system except
/// Linux, so this is the system call, not a new dependency (ADR-0002).
const libc_fifo = struct {
    extern "c" fn mkfifo(path: [*:0]const u8, mode: std.c.mode_t) c_int;
};

pub const Jobserver = struct {
    /// The private non-blocking descriptor that zmake reads tokens from.
    take_fd: posix.fd_t,
    /// The descriptor that zmake writes tokens back to.
    give_fd: posix.fd_t,
    /// The pipe ends that child processes inherit. Empty for a fifo.
    files: []const std.Io.File,
    /// The `--jobserver-auth` value for child processes: `R,W` or `fifo:PATH`.
    auth: []const u8,
    /// The token bytes that zmake holds. zmake writes the same bytes back.
    held: [ast.limits.jobs_max]u8 = undefined,
    held_len: u32 = 0,
    /// The fifo that this server made. `remove` deletes it at the end.
    fifo_path: ?[:0]const u8 = null,

    /// Create a pool with `jobs - 1` tokens. zmake holds the implicit token.
    /// `tmp_dir` holds the fifo of the fifo style.
    pub fn initServer(arena: std.mem.Allocator, jobs: u32, style: cli.JobserverStyle, tmp_dir: []const u8) Error!Jobserver {
        assert(jobs > 1 and jobs <= ast.limits.jobs_max);
        assert(tmp_dir.len > 0);
        return switch (style) {
            .pipe => if (is_linux) initPipeServer(arena, jobs) else error.Unsupported,
            .fifo => initFifoServer(arena, jobs, tmp_dir),
        };
    }

    /// A named fifo in `tmp_dir`. zmake opens it read-write with `O_NONBLOCK`,
    /// so the fifo always has a writer and a read never blocks.
    fn initFifoServer(arena: std.mem.Allocator, jobs: u32, tmp_dir: []const u8) Error!Jobserver {
        assert(jobs > 1);
        const path = try std.fmt.allocPrintSentinel(arena, "{s}/zmake-jobserver-{d}", .{ tmp_dir, processId() }, 0);
        try makeFifo(path);
        const fd = posix.openat(posix.AT.FDCWD, path, .{ .ACCMODE = .RDWR, .NONBLOCK = true, .CLOEXEC = true }, 0) catch return error.Jobserver;
        var i: u32 = 0;
        while (i + 1 < jobs) : (i += 1) try writeByte(fd, '+');
        const auth = try std.mem.concat(arena, u8, &.{ "fifo:", path });
        assert(fd >= 0);
        return .{ .take_fd = fd, .give_fd = fd, .files = &.{}, .auth = auth, .fifo_path = path };
    }

    /// Delete the fifo of a fifo server at the end of the run.
    pub fn remove(js: *Jobserver) void {
        assert(js.held_len <= js.held.len);
        const path = js.fifo_path orelse return;
        if (posix.errno(posix.system.unlinkat(posix.AT.FDCWD, path, 0)) != .SUCCESS) return;
        js.fifo_path = null;
        assert(js.fifo_path == null);
    }

    fn initPipeServer(arena: std.mem.Allocator, jobs: u32) Error!Jobserver {
        assert(is_linux);
        var fds: [2]posix.fd_t = undefined;
        if (posix.errno(posix.system.pipe2(&fds, .{ .CLOEXEC = true })) != .SUCCESS) return error.Jobserver;
        var i: u32 = 0;
        while (i + 1 < jobs) : (i += 1) try writeByte(fds[1], '+');
        const files = try inheritFiles(arena, fds);
        const auth = try std.fmt.allocPrint(arena, "{d},{d}", .{ fds[0], fds[1] });
        const take = try reopenNonblocking(arena, fds[0]);
        assert(take != fds[0]);
        assert(files.len == 2);
        return .{ .take_fd = take, .give_fd = fds[1], .files = files, .auth = auth };
    }

    /// Join the pool of a parent make. Return null when the descriptors are not
    /// open: the parent did not mark the recipe line with `+` or `$(MAKE)`.
    pub fn initClient(arena: std.mem.Allocator, auth: []const u8) Error!?Jobserver {
        assert(auth.len > 0);
        if (std.mem.startsWith(u8, auth, "fifo:")) {
            const path = auth["fifo:".len..];
            const fd = posix.openat(posix.AT.FDCWD, path, .{ .ACCMODE = .RDWR, .NONBLOCK = true, .CLOEXEC = true }, 0) catch return null;
            return .{ .take_fd = fd, .give_fd = fd, .files = &.{}, .auth = auth };
        }
        const comma = std.mem.indexOfScalar(u8, auth, ',') orelse return error.Jobserver;
        const r = std.fmt.parseInt(posix.fd_t, auth[0..comma], 10) catch return error.Jobserver;
        const w = std.fmt.parseInt(posix.fd_t, auth[comma + 1 ..], 10) catch return error.Jobserver;
        if (r < 0 or w < 0) return null;
        if (!isOpen(r) or !isOpen(w)) return null;
        // A private non-blocking descriptor for a pipe needs /proc (ADR-0008).
        if (!is_linux) return error.Unsupported;
        const take = reopenNonblocking(arena, r) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.Unsupported,
        };
        assert(take >= 0);
        return .{ .take_fd = take, .give_fd = w, .files = try inheritFiles(arena, .{ r, w }), .auth = auth };
    }

    /// Take one token without blocking. Return false when the pool is empty.
    pub fn tryAcquire(js: *Jobserver) Error!bool {
        assert(js.held_len < js.held.len);
        var byte: [1]u8 = undefined;
        const n = posix.read(js.take_fd, &byte) catch |err| switch (err) {
            error.WouldBlock => return false,
            else => return error.Jobserver,
        };
        if (n == 0) return false;
        js.held[js.held_len] = byte[0];
        js.held_len += 1;
        assert(js.held_len <= js.held.len);
        return true;
    }

    /// Return one token to the pool.
    pub fn release(js: *Jobserver) Error!void {
        assert(js.held_len > 0);
        js.held_len -= 1;
        try writeByte(js.give_fd, js.held[js.held_len]);
        assert(js.held_len < js.held.len);
    }

    /// Return every held token.
    pub fn releaseAll(js: *Jobserver) Error!void {
        assert(js.held_len <= js.held.len);
        var budget: u32 = ast.limits.jobs_max;
        while (js.held_len > 0 and budget > 0) : (budget -= 1) try js.release();
        assert(js.held_len == 0);
    }
};

fn inheritFiles(arena: std.mem.Allocator, fds: [2]posix.fd_t) Error![]const std.Io.File {
    assert(fds[0] >= 0 and fds[1] >= 0);
    const files = try arena.alloc(std.Io.File, 2);
    for (fds, files) |fd, *f| f.* = .{ .handle = fd, .flags = .{ .nonblocking = false } };
    assert(files.len == 2);
    return files;
}

fn writeByte(fd: posix.fd_t, byte: u8) Error!void {
    assert(fd >= 0);
    var budget: u32 = 100;
    while (budget > 0) : (budget -= 1) {
        const rc = posix.system.write(fd, @ptrCast(&byte), 1);
        switch (posix.errno(rc)) {
            .SUCCESS => return,
            .INTR, .AGAIN => continue,
            else => return error.Jobserver,
        }
    }
    return error.Jobserver;
}

fn isOpen(fd: posix.fd_t) bool {
    assert(fd >= 0);
    return posix.errno(posix.system.fcntl(fd, posix.F.GETFD, @as(usize, 0))) == .SUCCESS;
}

fn processId() i64 {
    const pid: i64 = if (is_linux) std.os.linux.getpid() else std.c.getpid();
    assert(pid > 0);
    assert(pid <= std.math.maxInt(i32));
    return pid;
}

/// Make a named fifo that only this user can read and write.
fn makeFifo(path: [:0]const u8) Error!void {
    assert(path.len > 0);
    const ok = if (is_linux)
        posix.errno(std.os.linux.mknodat(posix.AT.FDCWD, path, std.os.linux.S.IFIFO | 0o600, 0)) == .SUCCESS
    else
        libc_fifo.mkfifo(path, 0o600) == 0;
    if (!ok) return error.Jobserver;
    assert(ok);
}

/// Open the pipe end again through /proc, with O_NONBLOCK on the new descriptor only.
fn reopenNonblocking(arena: std.mem.Allocator, fd: posix.fd_t) Error!posix.fd_t {
    assert(fd >= 0);
    const path = try std.fmt.allocPrint(arena, "/proc/self/fd/{d}", .{fd});
    const new = posix.openat(posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true }, 0) catch return error.Jobserver;
    assert(new >= 0);
    return new;
}

/// The settings that a parent make passes in `MAKEFLAGS`.
pub const Makeflags = struct {
    flags: cli.Flags = .{},
    jobs: ?u32 = null,
    auth: ?[]const u8 = null,
    overrides: []const cli.Override = &.{},
};

/// Read the GNU `MAKEFLAGS` forms that zmake uses: the single-letter group
/// (`n`), `-jN`, `--jobserver-auth=X`, `--jobserver-fds=X` and `-- VAR=value`.
pub fn parseMakeflags(arena: std.mem.Allocator, text: []const u8) Error!Makeflags {
    var mf: Makeflags = .{};
    var overrides: std.ArrayList(cli.Override) = .empty;
    const words = try splitEscaped(arena, text);
    var first = true;
    var after_dashes = false;
    for (words) |word| {
        defer first = false;
        assert(word.len > 0);
        if (after_dashes) {
            const eq = std.mem.indexOfScalar(u8, word, '=') orelse continue;
            if (eq == 0) continue;
            const simple = word[eq - 1] == ':';
            const name = word[0 .. eq - @intFromBool(simple)];
            if (name.len > 0) try overrides.append(arena, .{ .name = name, .value = word[eq + 1 ..], .simple = simple });
        } else if (std.mem.eql(u8, word, "--")) {
            after_dashes = true;
        } else if (first and word[0] != '-' and std.mem.indexOfScalar(u8, word, '=') == null) {
            mf.flags = cli.Flags.fromLetters(word);
        } else if (std.mem.startsWith(u8, word, "--jobserver-auth=") or std.mem.startsWith(u8, word, "--jobserver-fds=")) {
            mf.auth = word[std.mem.indexOfScalar(u8, word, '=').? + 1 ..];
        } else if (std.mem.startsWith(u8, word, "-j")) {
            mf.jobs = std.fmt.parseInt(u32, word[2..], 10) catch null;
        }
    }
    mf.overrides = overrides.items;
    assert(mf.overrides.len <= text.len);
    return mf;
}

/// Build the `MAKEFLAGS` value for child processes.
pub fn composeMakeflags(arena: std.mem.Allocator, flags: cli.Flags, jobs: u32, auth: ?[]const u8, overrides: []const cli.Override) error{OutOfMemory}![]const u8 {
    assert(jobs >= 1);
    var out: std.ArrayList(u8) = .empty;
    var buf: [16]u8 = undefined;
    try out.appendSlice(arena, flags.letters(&buf));
    if (jobs > 1) try out.print(arena, " -j{d}", .{jobs});
    if (auth) |a| {
        try out.print(arena, " --jobserver-auth={s}", .{a});
        if (!std.mem.startsWith(u8, a, "fifo:")) try out.print(arena, " --jobserver-fds={s}", .{a});
    }
    if (overrides.len > 0) {
        try out.appendSlice(arena, " --");
        // GNU Make writes the overrides in the reverse order of its input.
        var i = overrides.len;
        while (i > 0) {
            i -= 1;
            const o = overrides[i];
            try out.append(arena, ' ');
            try appendEscaped(arena, &out, o.name);
            try out.appendSlice(arena, if (o.simple) ":=" else "=");
            try appendEscaped(arena, &out, o.value);
        }
    }
    assert(out.items.len >= @intFromBool(flags.dry_run));
    return out.items;
}

/// Write `s` with a backslash before each space, tab and backslash, as GNU
/// Make does in `MAKEFLAGS`.
fn appendEscaped(arena: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) error{OutOfMemory}!void {
    const before = out.items.len;
    for (s) |c| {
        if (c == ' ' or c == '\t' or c == '\\') try out.append(arena, '\\');
        try out.append(arena, c);
    }
    assert(out.items.len >= before + s.len);
    assert(out.items.len <= before + 2 * s.len);
}

/// Split `MAKEFLAGS` at white space that no backslash escapes. A backslash
/// makes the next character literal.
fn splitEscaped(arena: std.mem.Allocator, text: []const u8) Error![]const []const u8 {
    var words: std.ArrayList([]const u8) = .empty;
    var word: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '\\' and i + 1 < text.len) {
            i += 1;
            try word.append(arena, text[i]);
        } else if (c == ' ' or c == '\t') {
            if (word.items.len > 0) try words.append(arena, try word.toOwnedSlice(arena));
        } else {
            try word.append(arena, c);
        }
    }
    if (word.items.len > 0) try words.append(arena, try word.toOwnedSlice(arena));
    assert(i == text.len);
    assert(words.items.len <= text.len);
    return words.items;
}

const testing = std.testing;

test "server pool hands out jobs - 1 tokens" {
    if (!is_linux) return error.SkipZigTest; // The pipe style needs /proc (ADR-0020).
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var js = try Jobserver.initServer(arena.allocator(), 3, .pipe, "/tmp");
    try testing.expect(try js.tryAcquire());
    try testing.expect(try js.tryAcquire());
    try testing.expect(!try js.tryAcquire());
    try js.release();
    try testing.expect(try js.tryAcquire());
    try js.releaseAll();
    try testing.expectEqual(@as(u32, 0), js.held_len);
}

test "fifo server: the portable style" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realPathFileAlloc(testing.io, ".", arena.allocator());
    var js = try Jobserver.initServer(arena.allocator(), 3, .fifo, dir);
    try testing.expect(std.mem.startsWith(u8, js.auth, "fifo:"));
    try testing.expectEqual(@as(usize, 0), js.files.len);
    try testing.expect(try js.tryAcquire());
    var client = (try Jobserver.initClient(arena.allocator(), js.auth)).?;
    try testing.expect(try client.tryAcquire());
    try testing.expect(!(try js.tryAcquire()));
    try client.releaseAll();
    try testing.expect(try js.tryAcquire());
    try js.releaseAll();
    js.remove();
    try testing.expect(js.fifo_path == null);
}

test "pipe style off Linux is unsupported" {
    if (is_linux) return error.SkipZigTest;
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.Unsupported, Jobserver.initServer(arena.allocator(), 2, .pipe, "/tmp"));
    try testing.expectEqual(cli.JobserverStyle.fifo, default_style);
}

test "client joins a pool through R,W" {
    if (!is_linux) return error.SkipZigTest; // The pipe style needs /proc (ADR-0020).
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const server = try Jobserver.initServer(arena.allocator(), 2, .pipe, "/tmp");
    var client = (try Jobserver.initClient(arena.allocator(), server.auth)).?;
    try testing.expect(try client.tryAcquire());
    try testing.expect(!try client.tryAcquire());
    try client.releaseAll();
    try testing.expect((try Jobserver.initClient(arena.allocator(), "900,901")) == null);
}

test "parse MAKEFLAGS" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const mf = try parseMakeflags(arena.allocator(), "n -j4 --jobserver-auth=3,4 -- CC=clang X=1");
    try testing.expect(mf.flags.dry_run);
    try testing.expectEqual(@as(?u32, 4), mf.jobs);
    try testing.expectEqualStrings("3,4", mf.auth.?);
    try testing.expectEqual(@as(usize, 2), mf.overrides.len);
    try testing.expectEqualStrings("clang", mf.overrides[0].value);
    const quoted = try parseMakeflags(arena.allocator(), "s -- W=x\\\\\\ y Z=tab\\\there Y=c\\\\d X=a\\ b S:=1");
    try testing.expect(quoted.flags.silent);
    try testing.expectEqual(@as(usize, 5), quoted.overrides.len);
    try testing.expectEqualStrings("x\\ y", quoted.overrides[0].value);
    try testing.expectEqualStrings("tab\there", quoted.overrides[1].value);
    try testing.expectEqualStrings("c\\d", quoted.overrides[2].value);
    try testing.expectEqualStrings("a b", quoted.overrides[3].value);
    try testing.expect(quoted.overrides[4].simple);
    const back = try composeMakeflags(arena.allocator(), .{ .silent = true }, 1, null, quoted.overrides);
    try testing.expectEqualStrings("s -- S:=1 X=a\\ b Y=c\\\\d Z=tab\\\there W=x\\\\\\ y", back);
    const plain = try parseMakeflags(arena.allocator(), " --jobserver-auth=fifo:/tmp/GMfifo1 -j");
    try testing.expect(!plain.flags.dry_run);
    try testing.expectEqualStrings("fifo:/tmp/GMfifo1", plain.auth.?);
}

test "compose MAKEFLAGS" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const o = [_]cli.Override{.{ .name = "CC", .value = "clang", .simple = false }};
    const got = try composeMakeflags(arena.allocator(), .{ .dry_run = true }, 4, "3,4", &o);
    try testing.expectEqualStrings("n -j4 --jobserver-auth=3,4 --jobserver-fds=3,4 -- CC=clang", got);
    try testing.expectEqualStrings("", try composeMakeflags(arena.allocator(), .{}, 1, null, &.{}));
    const no_rules = try composeMakeflags(arena.allocator(), .{ .dry_run = true, .no_builtin_rules = true, .no_builtin_variables = true }, 1, null, &.{});
    try testing.expectEqualStrings("nrR", no_rules);
    const back = (try parseMakeflags(arena.allocator(), no_rules)).flags;
    try testing.expect(back.dry_run and back.no_builtin_rules and back.no_builtin_variables);
}
