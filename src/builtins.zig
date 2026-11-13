//! The eager built-in functions: all arguments are expanded before the call.
//! The evaluator handles the lazy ones (`if`, `and`, `or`, `intcmp`, `foreach`,
//! `let`, `call`) on its frame stack. Nothing here expands text, so no call
//! leads back into `Evaluator.expand` (ADR-0003, rule R1).

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const ast = @import("ast.zig");
const fns = @import("functions.zig");
const textfns = @import("textfns.zig");
const eval = @import("eval.zig");

const Evaluator = eval.Evaluator;
const Error = eval.Error;
const Func = eval.Func;
const ws = fns.whitespace;

/// Apply `func` to its expanded arguments. `auto` holds the automatic
/// variables of a recipe, or null.
pub fn apply(ev: *Evaluator, func: Func, args: []const []const u8, auto: ?*const eval.Auto) Error![]const u8 {
    assert(args.len >= 1 and args.len <= ast.limits.function_args_max);
    assert(func != .ref and func != .subst_ref);
    return switch (func) {
        .word, .wordlist => applyWords(ev, func, args),
        .wildcard, .shell, .abspath, .realpath, .file => applySystem(ev, func, args),
        .value, .origin, .flavor => applyVariable(ev, func, args, auto),
        .@"error", .warning, .info => applyMessage(ev, func, args),
        .ref, .subst_ref, .@"if", .@"and", .@"or", .intcmp, .foreach, .let, .call => unreachable,
        else => applyText(ev.arena, func, args),
    };
}

/// The pure text and file name functions.
fn applyText(arena: std.mem.Allocator, func: Func, r: []const []const u8) error{OutOfMemory}![]const u8 {
    assert(r.len >= 1);
    const out: []const u8 = switch (func) {
        .subst => try fns.subst(arena, r[0], r[1], r[2]),
        .patsubst => try fns.patsubst(arena, std.mem.trim(u8, r[0], ws), std.mem.trim(u8, r[1], ws), r[2]),
        .filter => try textfns.filter(arena, r[0], r[1], true),
        .filter_out => try textfns.filter(arena, r[0], r[1], false),
        .findstring => textfns.findstring(r[0], r[1]),
        .sort => try textfns.sort(arena, r[0]),
        .strip => try textfns.strip(arena, r[0]),
        .words => try textfns.countWords(arena, r[0]),
        .firstword => textfns.edgeWord(r[0], false),
        .lastword => textfns.edgeWord(r[0], true),
        .dir => try textfns.namePart(arena, r[0], .dir),
        .notdir => try textfns.namePart(arena, r[0], .notdir),
        .suffix => try textfns.namePart(arena, r[0], .suffix),
        .basename => try textfns.namePart(arena, r[0], .basename),
        .addsuffix => try textfns.addAffix(arena, r[0], r[1], true),
        .addprefix => try textfns.addAffix(arena, r[0], r[1], false),
        .join => try textfns.join(arena, r[0], r[1]),
        else => unreachable,
    };
    assert(out.len <= ast.limits.expansion_bytes_max * 2);
    return out;
}

/// `$(word n,text)` and `$(wordlist start,end,text)`, with the GNU Make messages.
fn applyWords(ev: *Evaluator, func: Func, r: []const []const u8) Error![]const u8 {
    assert(func == .word or func == .wordlist);
    const name: []const u8 = if (func == .word) "word" else "wordlist";
    const start = try ev.parseInt("first", name, r[0]);
    if (func == .word) {
        if (start <= 0) return ev.fail("first argument to 'word' function must be greater than 0", .{});
        const n: usize = @intCast(start);
        return textfns.wordlist(ev.arena, n, n, r[1]);
    }
    if (start <= 0) return ev.fail("invalid first argument to 'wordlist' function: '{d}'", .{start});
    const end = try ev.parseInt("second", name, r[1]);
    if (end < 0) return ev.fail("invalid second argument to 'wordlist' function: '{d}'", .{end});
    assert(start >= 1 and end >= 0);
    return textfns.wordlist(ev.arena, @intCast(start), @intCast(end), r[2]);
}

/// The functions that read the disk or run commands.
fn applySystem(ev: *Evaluator, func: Func, r: []const []const u8) Error![]const u8 {
    assert(r.len >= 1);
    assert(func == .wildcard or func == .shell or func == .abspath or func == .realpath or func == .file);
    const a = ev.arena;
    switch (func) {
        .wildcard => return fns.wildcard(a, ev.io, ev.dir, r[0]) catch |err| return functionError(ev, "wildcard", err),
        .shell => {
            const sh = if (ev.lookup("SHELL")) |v| v.value else "/bin/sh";
            return fns.shell(a, ev.io, sh, r[0]) catch |err| return functionError(ev, "shell", err);
        },
        .abspath => return textfns.abspath(a, try currentDir(ev), r[0]),
        .realpath => return realpath(ev, r[0]),
        .file => return fileFunction(ev, r),
        else => unreachable,
    }
}

fn functionError(ev: *Evaluator, name: []const u8, err: fns.Error) Error {
    assert(name.len > 0);
    assert(ev.diag.len <= @TypeOf(ev.diag.*).capacity);
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => ev.fail("function '{s}' failed: {s}", .{ name, @errorName(err) }),
    };
}

/// The absolute working directory of the process, read once per evaluator.
fn currentDir(ev: *Evaluator) Error![]const u8 {
    if (ev.cwd) |c| return c;
    const path = std.process.currentPathAlloc(ev.io, ev.arena) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return ev.fail("cannot read the working directory: {s}", .{@errorName(err)}),
    };
    assert(path.len > 0 and path[0] == '/');
    ev.cwd = path;
    assert(ev.cwd != null);
    return path;
}

/// `$(realpath names)`: the canonical path of each name that exists.
fn realpath(ev: *Evaluator, text: []const u8) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, ws);
    while (it.next()) |w| {
        assert(w.len > 0);
        const real = ev.dir.realPathFileAlloc(ev.io, w, ev.arena) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        try fns.appendWord(ev.arena, &out, real);
    }
    assert(out.items.len == 0 or out.items[0] == '/');
    return out.items;
}

const FileOp = enum { read, write, append };

/// `$(file >name,text)`, `$(file >>name,text)` and `$(file <name)`. A write adds
/// a newline when the text does not end with one. A read drops one final newline.
fn fileFunction(ev: *Evaluator, r: []const []const u8) Error![]const u8 {
    assert(r.len == 1 or r.len == 2);
    const spec = std.mem.trimStart(u8, r[0], ws);
    const op: FileOp, const skip: usize = if (std.mem.startsWith(u8, spec, ">>"))
        .{ .append, 2 }
    else if (std.mem.startsWith(u8, spec, ">"))
        .{ .write, 1 }
    else if (std.mem.startsWith(u8, spec, "<"))
        .{ .read, 1 }
    else
        return ev.fail("file: invalid file operation: {s}", .{spec});
    const name = std.mem.trim(u8, spec[skip..], ws);
    if (name.len == 0) return ev.fail("file: missing filename", .{});
    if (op == .read) {
        if (r.len > 1) return ev.fail("file: too many arguments", .{});
        return readFile(ev, name);
    }
    const text = if (r.len > 1) r[1] else "";
    try writeFile(ev, name, text, op == .append);
    assert(name.len > 0);
    return "";
}

fn readFile(ev: *Evaluator, name: []const u8) Error![]const u8 {
    const data = try readRaw(ev, name);
    const text = if (std.mem.endsWith(u8, data, "\n")) data[0 .. data.len - 1] else data;
    assert(text.len + 1 >= data.len);
    assert(text.len <= ast.limits.expansion_bytes_max);
    return text;
}

/// The bytes of file `name`, or empty when it does not exist.
fn readRaw(ev: *Evaluator, name: []const u8) Error![]const u8 {
    assert(name.len > 0);
    const limit: Io.Limit = .limited(ast.limits.expansion_bytes_max);
    const data = ev.dir.readFileAlloc(ev.io, name, ev.arena, limit) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound => return "",
        else => return ev.fail("open: {s}: {s}", .{ name, @errorName(err) }),
    };
    assert(data.len <= ast.limits.expansion_bytes_max);
    return data;
}

fn writeFile(ev: *Evaluator, name: []const u8, text: []const u8, append: bool) Error!void {
    assert(name.len > 0);
    const newline: []const u8 = if (text.len > 0 and text[text.len - 1] != '\n') "\n" else "";
    const old = if (append) try readRaw(ev, name) else "";
    const data = try std.mem.concat(ev.arena, u8, &.{ old, text, newline });
    ev.dir.writeFile(ev.io, .{ .sub_path = name, .data = data }) catch |err| {
        return ev.fail("open: {s}: {s}", .{ name, @errorName(err) });
    };
    assert(data.len >= text.len);
}

/// `$(value v)`, `$(origin v)` and `$(flavor v)`.
fn applyVariable(ev: *Evaluator, func: Func, r: []const []const u8, auto: ?*const eval.Auto) Error![]const u8 {
    assert(r.len == 1);
    const name = std.mem.trim(u8, r[0], ws);
    if (name.len == 0) return if (func == .value) "" else "undefined";
    if (auto != null and func != .flavor) {
        if (try ev.autoValue(name, auto)) |value| return if (func == .origin) "automatic" else value;
    }
    const v = ev.lookup(name) orelse return if (func == .value) "" else "undefined";
    assert(name.len > 0);
    return switch (func) {
        .value => v.value,
        .origin => v.origin.text(),
        .flavor => if (v.recursive) "recursive" else "simple",
        else => unreachable,
    };
}

/// `$(error text)` stops. `$(warning text)` prints `file:line: text` on stderr.
/// `$(info text)` prints the text on stdout.
fn applyMessage(ev: *Evaluator, func: Func, r: []const []const u8) Error![]const u8 {
    assert(r.len == 1);
    const text = r[0];
    switch (func) {
        .@"error" => return ev.fail("{s}", .{text}),
        .warning => {
            const msg = if (ev.line > 0)
                try std.fmt.allocPrint(ev.arena, "{s}:{d}: {s}\n", .{ ev.filename, ev.line, text })
            else
                try std.fmt.allocPrint(ev.arena, "{s}\n", .{text});
            Io.File.stderr().writeStreamingAll(ev.io, msg) catch return ev.fail("cannot write to stderr", .{});
        },
        .info => {
            const msg = try std.mem.concat(ev.arena, u8, &.{ text, "\n" });
            Io.File.stdout().writeStreamingAll(ev.io, msg) catch return ev.fail("cannot write to stdout", .{});
        },
        else => unreachable,
    }
    assert(func != .@"error");
    return "";
}
