//! Exact-case file names. The default macOS file system ignores case, so
//! `access("util.C")` succeeds when only `util.c` exists. GNU Make looks a
//! name up in a cached listing of its directory, with exact case, so it does
//! not see `util.C` (ADR-0023). zmake does the same on macOS. Linux and the
//! BSDs compare case already, so zmake skips the check there.

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const Io = std.Io;

/// True on systems whose default file system ignores case.
pub const needed = builtin.os.tag.isDarwin();

/// The entries of one directory that a listing reads at most (ADR-0003, rule R2).
pub const entries_max: u32 = 1_000_000;

pub const Error = error{ OutOfMemory, Io, LimitExceeded };

const Listing = struct {
    names: std.StringHashMapUnmanaged(void) = .empty,
    /// False when zmake cannot list the directory. A check then trusts `access`.
    readable: bool = true,
};

/// The listed names of each directory that a check reads, keyed by its path.
pub const Cache = struct {
    dirs: std.StringHashMapUnmanaged(Listing) = .empty,

    /// True when the directory of `path` lists the last component of `path`
    /// with this exact case. Call it after `access` finds `path`.
    pub fn listed(c: *Cache, arena: std.mem.Allocator, io: Io, dir: Io.Dir, path: []const u8) Error!bool {
        assert(path.len > 0);
        const split = splitPath(path) orelse return true;
        const gop = try c.dirs.getOrPut(arena, split.parent);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
            try readListing(arena, io, dir, split.parent, gop.value_ptr);
        }
        const listing = gop.value_ptr;
        assert(split.base.len > 0 and c.dirs.count() > 0);
        return !listing.readable or listing.names.contains(split.base);
    }
};

/// True when `dir` lists `name` with this exact case. `name` has no `/`. For
/// one check, such as the search for the input file.
pub fn listedIn(io: Io, dir: Io.Dir, name: []const u8) Error!bool {
    assert(name.len > 0);
    assert(std.mem.indexOfScalar(u8, name, '/') == null);
    var sub = dir.openDir(io, ".", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir, error.AccessDenied => return true,
        else => return error.Io,
    };
    defer sub.close(io);
    var iter = sub.iterate();
    var budget: u32 = entries_max;
    while (budget > 0) : (budget -= 1) {
        const entry = (iter.next(io) catch return error.Io) orelse return false;
        if (std.mem.eql(u8, entry.name, name)) return true;
    }
    return error.LimitExceeded;
}

fn readListing(arena: std.mem.Allocator, io: Io, dir: Io.Dir, parent: []const u8, listing: *Listing) Error!void {
    assert(parent.len > 0);
    assert(listing.names.count() == 0);
    var sub = dir.openDir(io, parent, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir, error.AccessDenied => {
            listing.readable = false;
            return;
        },
        else => return error.Io,
    };
    defer sub.close(io);
    var iter = sub.iterate();
    var budget: u32 = entries_max;
    while (budget > 0) : (budget -= 1) {
        const entry = (iter.next(io) catch return error.Io) orelse return;
        try listing.names.put(arena, try arena.dupe(u8, entry.name), {});
    }
    return error.LimitExceeded;
}

const Split = struct { parent: []const u8, base: []const u8 };

/// Split `path` into its directory and its last component. Return null when
/// no listing can hold the last component: `/`, `.` and `..`.
fn splitPath(path: []const u8) ?Split {
    assert(path.len > 0);
    const trimmed = std.mem.trimEnd(u8, path, "/");
    if (trimmed.len == 0) return null;
    const slash = std.mem.lastIndexOfScalar(u8, trimmed, '/');
    const base = if (slash) |i| trimmed[i + 1 ..] else trimmed;
    if (std.mem.eql(u8, base, ".") or std.mem.eql(u8, base, "..")) return null;
    const parent = if (slash) |i| (if (i == 0) "/" else trimmed[0..i]) else ".";
    assert(base.len > 0 and parent.len > 0);
    return .{ .parent = parent, .base = base };
}

const testing = std.testing;

test "split a path into directory and name" {
    const a = splitPath("src/lib/x.c").?;
    try testing.expectEqualStrings("src/lib", a.parent);
    try testing.expectEqualStrings("x.c", a.base);
    try testing.expectEqualStrings(".", splitPath("Makefile").?.parent);
    try testing.expectEqualStrings("/", splitPath("/etc").?.parent);
    try testing.expectEqualStrings("obj", splitPath("src/obj/").?.base);
    try testing.expect(splitPath("/") == null);
    try testing.expect(splitPath("a/..") == null);
}

test "a listing compares names with exact case" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "src");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "Makefile", .data = "" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "src/util.c", .data = "" });
    var cache: Cache = .{};
    try testing.expect(try cache.listed(a, testing.io, tmp.dir, "Makefile"));
    try testing.expect(!try cache.listed(a, testing.io, tmp.dir, "makefile"));
    try testing.expect(try cache.listed(a, testing.io, tmp.dir, "src/util.c"));
    try testing.expect(!try cache.listed(a, testing.io, tmp.dir, "src/util.C"));
    try testing.expect(try cache.listed(a, testing.io, tmp.dir, "src/"));
    try testing.expectEqual(@as(u32, 2), cache.dirs.count());
    try testing.expect(try listedIn(testing.io, tmp.dir, "Makefile"));
    try testing.expect(!try listedIn(testing.io, tmp.dir, "makefile"));
}
