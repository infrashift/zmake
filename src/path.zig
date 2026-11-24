//! File name rules of the host system. On Windows, `\` also separates the
//! parts of a name, and `C:/` or `C:\` starts an absolute name, as with the
//! `HAVE_DOS_PATHS` build of GNU Make (ADR-0029). Each function takes `dos`,
//! so the tests check the Windows rules on each system.

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

/// True on Windows: the file names use the DOS rules.
pub const dos = builtin.os.tag == .windows;

/// The shell that runs the recipe lines when the makefile does not set
/// `SHELL`. On Windows, the process search of `PATH` finds `sh.exe`, for
/// example the one of Git for Windows or MSYS2.
pub const default_shell: []const u8 = if (dos) "sh.exe" else "/bin/sh";

/// True when `c` separates the parts of a file name.
pub fn isSep(dos_paths: bool, c: u8) bool {
    const result = c == '/' or (dos_paths and c == '\\');
    assert(!result or c == '/' or c == '\\');
    assert(result or c != '/');
    return result;
}

/// True when `name` starts with `X:` and a separator.
pub fn hasDrive(dos_paths: bool, name: []const u8) bool {
    if (!dos_paths or name.len < 3) return false;
    const result = std.ascii.isAlphabetic(name[0]) and name[1] == ':' and isSep(true, name[2]);
    assert(dos_paths and name.len >= 3);
    assert(!result or name[1] == ':');
    return result;
}

/// True when `name` is an absolute file name.
pub fn isAbsolute(dos_paths: bool, name: []const u8) bool {
    if (name.len == 0) return false;
    const result = isSep(dos_paths, name[0]) or hasDrive(dos_paths, name);
    assert(name.len > 0);
    assert(result or name[0] != '/');
    return result;
}

/// The index of the last separator in `name`, or null.
pub fn lastSep(dos_paths: bool, name: []const u8) ?usize {
    var i = name.len;
    while (i > 0) {
        i -= 1;
        if (isSep(dos_paths, name[i])) return i;
    }
    assert(i == 0);
    assert(name.len == 0 or !isSep(dos_paths, name[0]));
    return null;
}

/// True when `name` holds a separator.
pub fn hasSep(dos_paths: bool, name: []const u8) bool {
    const result = lastSep(dos_paths, name) != null;
    assert(!result or name.len > 0);
    assert(result or std.mem.indexOfScalar(u8, name, '/') == null);
    return result;
}

/// True when the `:` at `i` of `text` is part of a drive name, as in
/// `C:/src/a.c: a.h`. The `:` follows one letter at the start of a word, and a
/// separator follows the `:`. Only the DOS rules have drive names.
pub fn isDriveColon(dos_paths: bool, text: []const u8, i: usize) bool {
    assert(i < text.len);
    if (!dos_paths or text[i] != ':' or i == 0 or i + 1 >= text.len) return false;
    if (!std.ascii.isAlphabetic(text[i - 1]) or !isSep(true, text[i + 1])) return false;
    const word_start = i == 1 or text[i - 2] == ' ' or text[i - 2] == '\t';
    assert(text[i] == ':');
    return word_start;
}

/// `name` with each `\` changed to `/`. A shell reads `\` as an escape, so
/// zmake gives the shell names with `/` on Windows. Off Windows, `name` stays.
pub fn forwardSlashes(arena: std.mem.Allocator, dos_paths: bool, name: []const u8) error{OutOfMemory}![]const u8 {
    if (!dos_paths or std.mem.indexOfScalar(u8, name, '\\') == null) return name;
    const out = try arena.dupe(u8, name);
    std.mem.replaceScalar(u8, out, '\\', '/');
    assert(out.len == name.len);
    assert(std.mem.indexOfScalar(u8, out, '\\') == null);
    return out;
}

const testing = std.testing;

test "the POSIX rules know only /" {
    try testing.expect(isSep(false, '/'));
    try testing.expect(!isSep(false, '\\'));
    try testing.expect(isAbsolute(false, "/usr"));
    try testing.expect(!isAbsolute(false, "C:/x"));
    try testing.expect(!isAbsolute(false, ""));
    try testing.expectEqual(@as(?usize, 3), lastSep(false, "a/b/c"));
    try testing.expectEqual(@as(?usize, null), lastSep(false, "a\\b"));
    try testing.expect(!isDriveColon(false, "C:/x: y", 1));
    try testing.expectEqualStrings("a\\b", try forwardSlashes(testing.allocator, false, "a\\b"));
}

test "the DOS rules add \\ and drive names" {
    try testing.expect(isSep(true, '\\'));
    try testing.expect(isAbsolute(true, "C:/x"));
    try testing.expect(isAbsolute(true, "c:\\x"));
    try testing.expect(isAbsolute(true, "\\x"));
    try testing.expect(!isAbsolute(true, "C:x"));
    try testing.expect(!isAbsolute(true, "src/x"));
    try testing.expectEqual(@as(?usize, 3), lastSep(true, "a/b\\c"));
    try testing.expect(hasSep(true, "out\\a.o"));
    try testing.expect(!hasSep(true, "a.o"));
}

test "a drive colon is not a rule separator" {
    try testing.expect(isDriveColon(true, "C:/x: y", 1));
    try testing.expect(!isDriveColon(true, "C:/x: y", 4));
    try testing.expect(isDriveColon(true, "app: d:\\lib\\x.a", 6));
    try testing.expect(!isDriveColon(true, "ab:/x", 2));
    try testing.expect(!isDriveColon(true, "a: b", 1));
    try testing.expect(!isDriveColon(true, "a:", 1));
}

test "forward slashes for the shell" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("C:/tools/zmake.exe", try forwardSlashes(a, true, "C:\\tools\\zmake.exe"));
    try testing.expectEqualStrings("a/b", try forwardSlashes(a, true, "a/b"));
}
